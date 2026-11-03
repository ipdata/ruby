# frozen_string_literal: true

require "net/http"
require "openssl"
require "json"
require "uri"

module IPData
  # HTTP client for the ipdata.co API.
  #
  # A client keeps one persistent HTTPS connection (HTTP/1.1 keep-alive) for
  # as long as it lives: the connection is opened on the first request and
  # reused for every later one, so only the first lookup pays the TCP and TLS
  # handshake. Create one client per process (or per API key or endpoint),
  # keep it, and call {#close} at shutdown.
  #
  # A client is safe to share between threads; requests are serialised on its
  # single connection, so use one client per thread for parallel lookups.
  # Create clients after forking: a client inherited from a parent process
  # notices the new process id and opens its own connection instead of
  # reusing (or closing) the parent's socket.
  #
  # @example Basic usage
  #   client = IPData::Client.new("YOUR_API_KEY")
  #   response = client.lookup("8.8.8.8")
  #   response.city  # => "Mountain View"
  #
  # @example EU endpoint (GDPR compliant)
  #   client = IPData::Client.eu("YOUR_API_KEY")
  #
  # @example With caching
  #   cache = IPData::Cache.new(max_size: 1024, ttl: 3600)
  #   client = IPData::Client.new("YOUR_API_KEY", cache: cache)
  class Client
    BASE_URL = "https://api.ipdata.co"
    EU_BASE_URL = "https://eu-api.ipdata.co"

    # Failures that mean a reused connection died before the server answered.
    RETRYABLE_ERRORS = [EOFError, IOError, Errno::ECONNRESET, Errno::EPIPE, OpenSSL::SSL::SSLError].freeze
    private_constant :RETRYABLE_ERRORS

    # @param api_key [String] Your ipdata API key
    # @param cache [IPData::Cache, nil] Optional LRU cache instance
    # @param timeout [Integer] HTTP open, read and write timeout in seconds (default: 30)
    # @param base_url [String, nil] Override the base URL (default: global endpoint)
    # @param keep_alive_timeout [Integer] Seconds an idle connection is kept before
    #   the next request opens a new one (default: 60)
    def initialize(api_key, cache: nil, timeout: 30, base_url: nil, keep_alive_timeout: 60)
      raise ArgumentError, "api_key is required" if api_key.nil? || api_key.empty?

      @api_key = api_key
      @cache = cache
      @timeout = timeout
      @keep_alive_timeout = keep_alive_timeout
      @base_uri = URI.parse(base_url || BASE_URL)
      @mutex = Mutex.new
      @connection = nil
      @connection_pid = nil
    end

    # Create a client configured for the EU endpoint.
    #
    # @param api_key [String] Your ipdata API key
    # @param opts [Hash] Additional options passed to {#initialize}
    # @return [Client]
    def self.eu(api_key, **opts)
      new(api_key, base_url: EU_BASE_URL, **opts)
    end

    # Look up geolocation data for an IP address.
    #
    # @param ip [String, nil] IP address to look up (nil for caller's own IP)
    # @param fields [Array<String>, nil] Specific fields to return
    # @param select_field [String, nil] A single field to extract (returns raw value)
    # @return [Response, Object] Response object, or raw value if select_field is used
    def lookup(ip = nil, fields: nil, select_field: nil)
      if select_field
        path = "/#{ip}/#{select_field}"
        data = get(path)
        return data
      end

      cache_key = build_cache_key(ip, fields)
      if @cache
        cached = @cache.get(cache_key)
        return cached if cached
      end

      path = ip ? "/#{ip}" : "/"
      params = {}
      params["fields"] = fields.join(",") if fields && !fields.empty?

      data = get(path, params)
      response = Response.new(data)

      @cache&.set(cache_key, response)
      response
    end

    # Look up geolocation data for multiple IP addresses.
    #
    # @param ips [Array<String>] IP addresses (max 100)
    # @param fields [Array<String>, nil] Specific fields to return
    # @return [Array<Response>]
    # @raise [ArgumentError] if more than 100 IPs are provided
    def bulk_lookup(ips, fields: nil)
      raise ArgumentError, "ips must be an Array" unless ips.is_a?(Array)
      raise ArgumentError, "maximum 100 IPs per bulk request" if ips.size > 100

      params = {}
      params["fields"] = fields.join(",") if fields && !fields.empty?

      data = post("/bulk", ips, params)
      data.map { |entry| Response.new(entry) }
    end

    # Close the persistent connection, if one is open.
    #
    # The client stays usable: the next request opens a new connection.
    #
    # @return [nil]
    def close
      @mutex.synchronize { discard_connection }
      nil
    end

    private

    def user_agent
      @user_agent ||= "ruby-ipdata/#{VERSION} Ruby/#{RUBY_VERSION} (#{RUBY_PLATFORM})"
    end

    def build_cache_key(ip, fields)
      key = ip || "_self"
      key = "#{key}:#{fields.sort.join(",")}" if fields && !fields.empty?
      key
    end

    def build_uri(path, params = {})
      uri = @base_uri.dup
      uri.path = path
      query_params = { "api-key" => @api_key }.merge(params)
      uri.query = URI.encode_www_form(query_params)
      uri
    end

    def get(path, params = {})
      uri = build_uri(path, params)

      request = Net::HTTP::Get.new(uri)
      request["Accept"] = "application/json"
      request["User-Agent"] = user_agent

      execute(request)
    end

    def post(path, body, params = {})
      uri = build_uri(path, params)

      request = Net::HTTP::Post.new(uri)
      request["Accept"] = "application/json"
      request["Content-Type"] = "application/json"
      request["User-Agent"] = user_agent
      request.body = JSON.generate(body)

      execute(request)
    end

    def execute(request)
      response = @mutex.synchronize { perform(request) }

      unless response.is_a?(Net::HTTPSuccess)
        raise Error.from_response(response.code.to_i, response.body)
      end

      JSON.parse(response.body)
    end

    # Send +request+ on the pooled connection. Must be called with @mutex held.
    #
    # The server may drop an idle connection without notice. Net::HTTP retries
    # idempotent requests (GET) on such a failure itself (max_retries); POST
    # /bulk is not idempotent, so Net::HTTP leaves it alone and it is retried
    # here instead: exactly once, on a fresh connection, and only when the
    # failure happened before any response byte arrived. An HTTP error status
    # is a response and is never retried.
    def perform(request)
      retried = false
      loop do
        http = connection
        responded = false
        begin
          return http.request(request) { responded = true }
        rescue *RETRYABLE_ERRORS
          discard_connection
          raise if retried || responded || request.method != "POST"

          retried = true
        end
      end
    end

    # The pooled Net::HTTP, opened on first use. A connection inherited from a
    # parent process is dropped without finish (the socket is shared with the
    # parent, so no TLS close_notify may be sent on it) and a new one opened.
    def connection
      discard_connection if @connection && @connection_pid != Process.pid
      @connection ||= connect
    end

    def connect
      http = Net::HTTP.new(@base_uri.host, @base_uri.port)
      http.use_ssl = @base_uri.scheme == "https"
      http.open_timeout = @timeout
      http.read_timeout = @timeout
      http.write_timeout = @timeout
      http.keep_alive_timeout = @keep_alive_timeout
      http.max_retries = 1
      http.start
      @connection_pid = Process.pid
      http
    end

    # Forget the pooled connection, finishing it only if this process opened it.
    def discard_connection
      http = @connection
      @connection = nil
      return unless http && @connection_pid == Process.pid

      http.finish if http.started?
    rescue IOError, SystemCallError
      nil
    end
  end
end
