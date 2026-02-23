# frozen_string_literal: true

require "net/http"
require "json"
require "uri"

module IPData
  # HTTP client for the ipdata.co API.
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

    # @param api_key [String] Your ipdata API key
    # @param cache [IPData::Cache, nil] Optional LRU cache instance
    # @param timeout [Integer] HTTP timeout in seconds (default: 30)
    # @param base_url [String, nil] Override the base URL (default: global endpoint)
    def initialize(api_key, cache: nil, timeout: 30, base_url: nil)
      raise ArgumentError, "api_key is required" if api_key.nil? || api_key.empty?

      @api_key = api_key
      @cache = cache
      @timeout = timeout
      @base_uri = URI.parse(base_url || BASE_URL)
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

      execute(uri, request)
    end

    def post(path, body, params = {})
      uri = build_uri(path, params)

      request = Net::HTTP::Post.new(uri)
      request["Accept"] = "application/json"
      request["Content-Type"] = "application/json"
      request["User-Agent"] = user_agent
      request.body = JSON.generate(body)

      execute(uri, request)
    end

    def execute(uri, request)
      http = Net::HTTP.new(uri.host, uri.port)
      http.use_ssl = true
      http.open_timeout = @timeout
      http.read_timeout = @timeout

      response = http.request(request)

      unless response.is_a?(Net::HTTPSuccess)
        raise Error.from_response(response.code.to_i, response.body)
      end

      JSON.parse(response.body)
    end
  end
end
