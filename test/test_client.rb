# frozen_string_literal: true

require_relative "test_helper"

class TestClient < Minitest::Test
  include IPDataFixtures

  API_KEY = "test-api-key-123"

  def setup
    @client = IPData::Client.new(API_KEY)
  end

  # --- Initialization ---

  def test_raises_on_nil_api_key
    assert_raises(ArgumentError) { IPData::Client.new(nil) }
  end

  def test_raises_on_empty_api_key
    assert_raises(ArgumentError) { IPData::Client.new("") }
  end

  def test_eu_client_factory
    client = IPData::Client.eu(API_KEY)
    assert_instance_of IPData::Client, client
  end

  def test_custom_base_url
    client = IPData::Client.new(API_KEY, base_url: "https://custom.example.com")
    assert_instance_of IPData::Client, client
  end

  def test_keep_alive_timeout_option
    client = IPData::Client.new(API_KEY, keep_alive_timeout: 30)
    assert_instance_of IPData::Client, client
  end

  # --- lookup ---

  def test_lookup_with_ip
    assert_request(:get, "/8.8.8.8", query: { "api-key" => API_KEY }) do
      response = @client.lookup("8.8.8.8")
      assert_instance_of IPData::Response, response
      assert_equal "8.8.8.8", response.ip
      assert_equal "Mountain View", response.city
    end
  end

  def test_lookup_without_ip_uses_root_path
    assert_request(:get, "/", query: { "api-key" => API_KEY }) do
      response = @client.lookup
      assert_instance_of IPData::Response, response
    end
  end

  def test_lookup_with_fields
    assert_request(:get, "/8.8.8.8", query: { "api-key" => API_KEY, "fields" => "ip,city" }) do
      response = @client.lookup("8.8.8.8", fields: ["ip", "city"])
      assert_instance_of IPData::Response, response
    end
  end

  def test_lookup_with_select_field
    assert_request(:get, "/8.8.8.8/city", query: { "api-key" => API_KEY }, body: '"Mountain View"') do
      result = @client.lookup("8.8.8.8", select_field: "city")
      assert_equal "Mountain View", result
    end
  end

  # --- bulk_lookup ---

  def test_bulk_lookup
    ips = ["8.8.8.8", "1.1.1.1"]
    body = JSON.generate(SAMPLE_BULK_RESPONSE)

    assert_request(:post, "/bulk", query: { "api-key" => API_KEY }, body: body, request_body: JSON.generate(ips)) do
      responses = @client.bulk_lookup(ips)
      assert_instance_of Array, responses
      assert_equal 2, responses.size
      assert_instance_of IPData::Response, responses[0]
      assert_equal "8.8.8.8", responses[0].ip
      assert_equal "1.1.1.1", responses[1].ip
    end
  end

  def test_bulk_lookup_with_fields
    ips = ["8.8.8.8"]
    body = JSON.generate([SAMPLE_RESPONSE])

    assert_request(:post, "/bulk", query: { "api-key" => API_KEY, "fields" => "ip,city" }, body: body) do
      responses = @client.bulk_lookup(ips, fields: ["ip", "city"])
      assert_equal 1, responses.size
    end
  end

  def test_bulk_lookup_raises_for_non_array
    assert_raises(ArgumentError) { @client.bulk_lookup("8.8.8.8") }
  end

  def test_bulk_lookup_raises_for_too_many_ips
    ips = (1..101).map { |i| "1.2.3.#{i % 256}" }
    assert_raises(ArgumentError) { @client.bulk_lookup(ips) }
  end

  def test_bulk_lookup_allows_exactly_100_ips
    ips = (1..100).map { |i| "1.2.3.#{i % 256}" }
    body = JSON.generate(ips.map { |ip| SAMPLE_RESPONSE.merge("ip" => ip) })

    assert_request(:post, "/bulk", query: { "api-key" => API_KEY }, body: body) do
      responses = @client.bulk_lookup(ips)
      assert_equal 100, responses.size
    end
  end

  # --- EU endpoint ---

  def test_eu_client_uses_eu_base_url
    client = IPData::Client.eu(API_KEY)

    called = false
    Net::HTTP.stub(:new, lambda { |host, port|
      assert_equal "eu-api.ipdata.co", host
      assert_equal 443, port
      called = true
      mock_http(stub_http_response)
    }) do
      client.lookup("8.8.8.8")
    end
    assert called, "Expected request to EU endpoint"
  end

  # --- Error handling ---

  def test_raises_authentication_error_on_401
    assert_error_response(401, '{"message": "Missing API key"}', IPData::AuthenticationError)
  end

  def test_raises_forbidden_error_on_403
    assert_error_response(403, '{"message": "Quota exceeded"}', IPData::ForbiddenError)
  end

  def test_raises_bad_request_error_on_400
    assert_error_response(400, '{"message": "Invalid IP"}', IPData::BadRequestError)
  end

  def test_raises_generic_error_on_500
    assert_error_response(500, '{"message": "Server error"}', IPData::Error)
  end

  # --- Caching ---

  def test_lookup_uses_cache
    cache = IPData::Cache.new
    client = IPData::Client.new(API_KEY, cache: cache)
    mock = mock_http(stub_http_response)

    Net::HTTP.stub(:new, ->(_h, _p) { mock }) do
      # First call hits the API
      client.lookup("8.8.8.8")
      assert_equal 1, mock.requests.size

      # Second call served from cache
      client.lookup("8.8.8.8")
      assert_equal 1, mock.requests.size
    end
  end

  def test_select_field_does_not_use_cache
    cache = IPData::Cache.new
    client = IPData::Client.new(API_KEY, cache: cache)
    mock = mock_http(stub_http_response(body: '"Mountain View"'))

    Net::HTTP.stub(:new, ->(_h, _p) { mock }) do
      client.lookup("8.8.8.8", select_field: "city")
      client.lookup("8.8.8.8", select_field: "city")
      assert_equal 2, mock.requests.size
    end
  end

  def test_different_fields_have_different_cache_keys
    cache = IPData::Cache.new
    client = IPData::Client.new(API_KEY, cache: cache)
    mock = mock_http(stub_http_response)

    Net::HTTP.stub(:new, ->(_h, _p) { mock }) do
      client.lookup("8.8.8.8", fields: ["ip"])
      client.lookup("8.8.8.8", fields: ["ip", "city"])
      assert_equal 2, mock.requests.size
    end
  end

  # --- User-Agent header ---

  def test_user_agent_header
    captured_request = nil

    mock = mock_http(stub_http_response) do |req|
      captured_request = req
    end

    Net::HTTP.stub(:new, ->(_h, _p) { mock }) do
      @client.lookup("8.8.8.8")
    end

    assert_match(/ruby-ipdata\/#{IPData::VERSION}/, captured_request["User-Agent"])
    assert_match(/Ruby\/#{RUBY_VERSION}/, captured_request["User-Agent"])
  end

  # --- Accept header ---

  def test_accept_json_header
    captured_request = nil

    mock = mock_http(stub_http_response) do |req|
      captured_request = req
    end

    Net::HTTP.stub(:new, ->(_h, _p) { mock }) do
      @client.lookup("8.8.8.8")
    end

    assert_equal "application/json", captured_request["Accept"]
  end

  # --- Connection reuse ---

  def test_consecutive_calls_reuse_one_connection
    answer = lambda do |req, &on_response|
      body = req.method == "POST" ? JSON.generate(SAMPLE_BULK_RESPONSE) : JSON.generate(SAMPLE_RESPONSE)
      response = stub_http_response(body: body)
      on_response&.call(response)
      response
    end

    connections = stub_connections(answer) do
      @client.lookup("8.8.8.8")
      @client.lookup("1.1.1.1")
      @client.bulk_lookup(["8.8.8.8", "1.1.1.1"])
    end

    assert_equal 1, connections.size, "expected one Net::HTTP object for the lifetime of the client"
    http = connections.first
    assert_equal %w[GET GET POST], http.requests.map(&:method)
    assert_equal 1, http.start_count
    assert http.started?, "the connection stays open between requests"
  end

  def test_connection_is_configured_from_options_and_started_before_use
    client = IPData::Client.new(API_KEY, timeout: 7, keep_alive_timeout: 12)
    connections = stub_connections { client.lookup("8.8.8.8") }

    http = connections.first
    assert_equal "api.ipdata.co", http.address
    assert_equal 443, http.port
    assert_equal true, http.settings[:use_ssl]
    assert_equal 7, http.settings[:open_timeout]
    assert_equal 7, http.settings[:read_timeout]
    assert_equal 7, http.settings[:write_timeout]
    assert_equal 12, http.settings[:keep_alive_timeout]
    assert_equal 1, http.settings[:max_retries]
    assert_equal 1, http.start_count
  end

  def test_keep_alive_timeout_defaults_to_60_seconds
    connections = stub_connections { @client.lookup("8.8.8.8") }
    assert_equal 60, connections.first.settings[:keep_alive_timeout]
  end

  def test_use_ssl_follows_the_base_url_scheme
    client = IPData::Client.new(API_KEY, base_url: "http://localhost:8080")
    connections = stub_connections { client.lookup("8.8.8.8") }

    http = connections.first
    assert_equal "localhost", http.address
    assert_equal 8080, http.port
    assert_equal false, http.settings[:use_ssl]
  end

  def test_close_finishes_the_connection
    connections = stub_connections { @client.lookup("8.8.8.8") }
    http = connections.first
    assert http.started?

    assert_nil @client.close

    refute http.started?
    assert_equal 1, http.finish_count
  end

  def test_close_without_a_connection_is_a_no_op
    assert_nil @client.close
    assert_nil @client.close
  end

  def test_lookup_after_close_opens_a_new_connection
    connections = stub_connections do
      @client.lookup("8.8.8.8")
      @client.close
      @client.lookup("8.8.8.8")
    end

    assert_equal 2, connections.size
    refute connections[0].started?
    assert connections[1].started?
    assert_equal [1, 1], connections.map { |http| http.requests.size }
  end

  def test_pid_change_reconnects_without_finishing_the_inherited_connection
    connections = stub_connections do
      @client.lookup("8.8.8.8")
      # Pretend the client was inherited by a forked child process.
      Process.stub(:pid, Process.pid + 1) { @client.lookup("8.8.8.8") }
    end

    assert_equal 2, connections.size
    inherited, own = connections
    assert inherited.started?, "the parent's connection must not be finished from the child"
    assert_equal 0, inherited.finish_count
    assert_equal 1, inherited.requests.size
    assert_equal 1, own.requests.size
  end

  def test_close_in_a_forked_child_leaves_the_inherited_connection_alone
    connections = stub_connections { @client.lookup("8.8.8.8") }

    Process.stub(:pid, Process.pid + 1) { @client.close }

    assert connections.first.started?
    assert_equal 0, connections.first.finish_count
  end

  def test_bulk_lookup_is_retried_once_on_a_dead_connection
    bulk = stub_http_response(body: JSON.generate(SAMPLE_BULK_RESPONSE))
    connections = stub_connections(EOFError.new("end of file reached"), bulk) do
      responses = @client.bulk_lookup(["8.8.8.8", "1.1.1.1"])
      assert_equal ["8.8.8.8", "1.1.1.1"], responses.map(&:ip)
    end

    assert_equal 2, connections.size, "the dead connection is discarded and a new one opened"
    dead, fresh = connections
    assert_equal 1, dead.requests.size
    assert_equal 1, dead.finish_count
    assert_equal 1, fresh.requests.size
    assert_equal "POST", fresh.requests.first.method
    assert_equal JSON.generate(["8.8.8.8", "1.1.1.1"]), fresh.requests.first.body
  end

  def test_bulk_lookup_is_retried_on_each_dead_connection_error
    errors = [
      IOError.new("closed stream"),
      Errno::ECONNRESET.new,
      Errno::EPIPE.new,
      OpenSSL::SSL::SSLError.new("SSL_read: unexpected eof while reading")
    ]

    errors.each do |error|
      client = IPData::Client.new(API_KEY)
      bulk = stub_http_response(body: JSON.generate([SAMPLE_RESPONSE]))
      connections = stub_connections(error, bulk) do
        assert_equal 1, client.bulk_lookup(["8.8.8.8"]).size, "expected a retry after #{error.class}"
      end
      assert_equal 2, connections.size, "expected a new connection after #{error.class}"
    end
  end

  def test_bulk_lookup_is_retried_only_once
    connections = stub_connections(EOFError.new("end of file reached")) do
      assert_raises(EOFError) { @client.bulk_lookup(["8.8.8.8"]) }
    end

    assert_equal 2, connections.size
    assert_equal [1, 1], connections.map { |http| http.requests.size }
  end

  def test_bulk_lookup_is_not_retried_after_response_bytes_arrived
    dies_mid_body = lambda do |_req, &on_response|
      on_response&.call(stub_http_response)
      raise EOFError, "end of file reached"
    end

    connections = stub_connections(dies_mid_body) do
      assert_raises(EOFError) { @client.bulk_lookup(["8.8.8.8"]) }
    end

    assert_equal 1, connections.size
    assert_equal 1, connections.first.requests.size
  end

  def test_bulk_lookup_is_not_retried_on_an_http_error_status
    failure = stub_http_response(status: "500", body: '{"message": "Server error"}')
    connections = stub_connections(failure) do
      assert_raises(IPData::Error) { @client.bulk_lookup(["8.8.8.8"]) }
    end

    assert_equal 1, connections.size
    assert_equal 1, connections.first.requests.size
  end

  def test_bulk_lookup_is_not_retried_on_a_timeout
    connections = stub_connections(Net::ReadTimeout.new) do
      assert_raises(Net::ReadTimeout) { @client.bulk_lookup(["8.8.8.8"]) }
    end

    assert_equal 1, connections.size
    assert_equal 1, connections.first.requests.size
  end

  def test_get_is_not_retried_by_the_client
    # Net::HTTP retries idempotent requests itself; the client must not add a second attempt.
    connections = stub_connections(EOFError.new("end of file reached")) do
      assert_raises(EOFError) { @client.lookup("8.8.8.8") }
    end

    assert_equal 1, connections.size
    assert_equal 1, connections.first.requests.size
  end

  def test_dead_connection_is_replaced_on_the_next_call
    connections = stub_connections(EOFError.new("end of file reached"), stub_http_response) do
      assert_raises(EOFError) { @client.lookup("8.8.8.8") }
      @client.lookup("8.8.8.8")
    end

    assert_equal 2, connections.size
    assert_equal 1, connections[0].finish_count
    assert connections[1].started?
  end

  def test_requests_from_several_threads_are_serialised_on_the_one_connection
    in_flight = 0
    max_in_flight = 0
    counter = Mutex.new
    one_at_a_time = lambda do |_req, &on_response|
      counter.synchronize do
        in_flight += 1
        max_in_flight = [max_in_flight, in_flight].max
      end
      Thread.pass
      response = stub_http_response
      on_response&.call(response)
      counter.synchronize { in_flight -= 1 }
      response
    end

    connections = stub_connections(one_at_a_time) do
      threads = Array.new(4) { Thread.new { 25.times { @client.lookup("8.8.8.8") } } }
      threads.each(&:join)
    end

    assert_equal 1, connections.size
    assert_equal 100, connections.first.requests.size
    assert_equal 1, max_in_flight, "requests must not overlap on the shared connection"
  end

  private

  # Helper to assert a request was made with expected parameters.
  def assert_request(method, path, query: {}, body: nil, request_body: nil)
    captured_request = nil
    response_body = body || JSON.generate(SAMPLE_RESPONSE)

    http_response = stub_http_response(body: response_body)
    mock = mock_http(http_response) do |req|
      captured_request = req
    end

    Net::HTTP.stub(:new, ->(_h, _p) { mock }) do
      yield
    end

    assert captured_request, "Expected HTTP request to be made"
    uri = URI.parse(captured_request.path.to_s + "?" + (captured_request.instance_variable_get(:@query) || ""))

    # Check path
    request_uri = URI.parse(captured_request.uri.to_s)
    assert_equal path, request_uri.path

    # Check query params
    actual_params = URI.decode_www_form(request_uri.query || "").to_h
    query.each do |k, v|
      assert_equal v, actual_params[k], "Expected query param #{k}=#{v}"
    end

    # Check request body for POST
    if request_body
      assert_equal request_body, captured_request.body
    end
  end

  # Helper to assert an error response is properly raised.
  def assert_error_response(status, body, error_class)
    http_response = stub_http_response(status: status.to_s, body: body)

    Net::HTTP.stub(:new, ->(_h, _p) { mock_http(http_response) }) do
      error = assert_raises(error_class) { @client.lookup("8.8.8.8") }
      assert_equal status, error.status_code
    end
  end

  # Create a fake Net::HTTP that answers every request with +outcome+ (see FakeHTTP).
  def mock_http(outcome, &on_request)
    FakeHTTP.new(outcome, &on_request)
  end

  # Stub Net::HTTP.new to hand out a new FakeHTTP per call and return every
  # connection the client opened. Connection i answers with outcomes[i] (the
  # last outcome repeats); with no outcomes every connection returns the
  # sample response.
  def stub_connections(*outcomes)
    outcomes = [stub_http_response] if outcomes.empty?
    connections = []

    Net::HTTP.stub(:new, lambda { |host, port|
      http = mock_http(outcomes.fetch(connections.size, outcomes.last))
      http.address = host
      http.port = port
      connections << http
      http
    }) do
      yield
    end

    connections
  end

  # Stand-in for Net::HTTP that records how the client configures and drives it.
  #
  # +outcome+ is the response to return, an exception to raise before any
  # response byte arrives (a dead connection), or a Proc called with the
  # request and the response block for finer control.
  class FakeHTTP
    attr_accessor :address, :port
    attr_reader :settings, :requests, :start_count, :finish_count

    def initialize(outcome, &on_request)
      @outcome = outcome
      @on_request = on_request
      @settings = {}
      @requests = []
      @started = false
      @start_count = 0
      @finish_count = 0
    end

    %i[use_ssl open_timeout read_timeout write_timeout keep_alive_timeout max_retries].each do |setting|
      define_method(:"#{setting}=") { |value| @settings[setting] = value }
    end

    def start
      raise IOError, "HTTP session already opened" if @started

      @started = true
      @start_count += 1
      self
    end

    def started?
      @started
    end

    def finish
      raise IOError, "HTTP session not yet started" unless @started

      @started = false
      @finish_count += 1
    end

    # Like Net::HTTP#request: yields the response once its headers arrived, then returns it.
    def request(req, &on_response)
      raise Minitest::Assertion, "request sent on a connection that was not started" unless @started

      @requests << req
      @on_request&.call(req)

      case @outcome
      when Proc then @outcome.call(req, &on_response)
      when Exception then raise @outcome
      else
        on_response&.call(@outcome)
        @outcome
      end
    end
  end
end
