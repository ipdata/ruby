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
    call_count = 0

    Net::HTTP.stub(:new, lambda { |_host, _port|
      call_count += 1
      mock_http(stub_http_response)
    }) do
      # First call hits the API
      client.lookup("8.8.8.8")
      assert_equal 1, call_count

      # Second call served from cache
      client.lookup("8.8.8.8")
      assert_equal 1, call_count
    end
  end

  def test_select_field_does_not_use_cache
    cache = IPData::Cache.new
    client = IPData::Client.new(API_KEY, cache: cache)
    call_count = 0

    Net::HTTP.stub(:new, lambda { |_host, _port|
      call_count += 1
      mock_http(stub_http_response(body: '"Mountain View"'))
    }) do
      client.lookup("8.8.8.8", select_field: "city")
      client.lookup("8.8.8.8", select_field: "city")
      assert_equal 2, call_count
    end
  end

  def test_different_fields_have_different_cache_keys
    cache = IPData::Cache.new
    client = IPData::Client.new(API_KEY, cache: cache)
    call_count = 0

    Net::HTTP.stub(:new, lambda { |_host, _port|
      call_count += 1
      mock_http(stub_http_response)
    }) do
      client.lookup("8.8.8.8", fields: ["ip"])
      client.lookup("8.8.8.8", fields: ["ip", "city"])
      assert_equal 2, call_count
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

  # Create a mock Net::HTTP object that returns the given response.
  def mock_http(response, &on_request)
    http = Object.new

    http.define_singleton_method(:use_ssl=) { |_v| }
    http.define_singleton_method(:open_timeout=) { |_v| }
    http.define_singleton_method(:read_timeout=) { |_v| }
    http.define_singleton_method(:request) do |req|
      on_request&.call(req)
      response
    end

    http
  end
end
