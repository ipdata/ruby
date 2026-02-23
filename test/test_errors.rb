# frozen_string_literal: true

require_relative "test_helper"

class TestErrors < Minitest::Test
  def test_error_has_message_and_status_code
    error = IPData::Error.new("something went wrong", 500)
    assert_equal "something went wrong", error.message
    assert_equal 500, error.status_code
  end

  def test_error_is_a_standard_error
    assert IPData::Error < StandardError
  end

  def test_authentication_error_from_401
    error = IPData::Error.from_response(401, '{"message": "You have not provided a valid API Key."}')
    assert_instance_of IPData::AuthenticationError, error
    assert_equal 401, error.status_code
    assert_equal "You have not provided a valid API Key.", error.message
  end

  def test_forbidden_error_from_403
    error = IPData::Error.from_response(403, '{"message": "You have exceeded your free tier limit."}')
    assert_instance_of IPData::ForbiddenError, error
    assert_equal 403, error.status_code
    assert_equal "You have exceeded your free tier limit.", error.message
  end

  def test_bad_request_error_from_400
    error = IPData::Error.from_response(400, '{"message": "invalid_ip is not a valid IPv4 or IPv6 address."}')
    assert_instance_of IPData::BadRequestError, error
    assert_equal 400, error.status_code
    assert_includes error.message, "not a valid"
  end

  def test_generic_error_from_unknown_status
    error = IPData::Error.from_response(502, '{"message": "Bad Gateway"}')
    assert_instance_of IPData::Error, error
    assert_equal 502, error.status_code
  end

  def test_error_from_empty_body
    error = IPData::Error.from_response(500, "")
    assert_equal "API request failed", error.message
    assert_equal 500, error.status_code
  end

  def test_error_from_nil_body
    error = IPData::Error.from_response(500, nil)
    assert_equal "API request failed", error.message
  end

  def test_error_from_non_json_body
    error = IPData::Error.from_response(500, "Internal Server Error")
    assert_equal "Internal Server Error", error.message
  end

  def test_error_inheritance
    assert IPData::AuthenticationError < IPData::Error
    assert IPData::ForbiddenError < IPData::Error
    assert IPData::BadRequestError < IPData::Error
  end

  def test_error_can_be_rescued_as_standard_error
    assert_raises(StandardError) do
      raise IPData::AuthenticationError.new("test", 401)
    end
  end
end
