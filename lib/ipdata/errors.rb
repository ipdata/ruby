# frozen_string_literal: true

require "json"

module IPData
  # Base error class for all ipdata API errors.
  # Carries the HTTP status code and API error message.
  class Error < StandardError
    attr_reader :status_code

    def initialize(message, status_code = nil)
      @status_code = status_code
      super(message)
    end

    # Build the appropriate error subclass from an HTTP response.
    def self.from_response(status, body)
      message = parse_message(body) || "API request failed"
      klass = case status
              when 400 then BadRequestError
              when 401 then AuthenticationError
              when 403 then ForbiddenError
              else Error
              end
      klass.new(message, status)
    end

    def self.parse_message(body)
      return nil if body.nil? || body.empty?

      data = JSON.parse(body)
      data["message"]
    rescue JSON::ParserError
      body
    end
    private_class_method :parse_message
  end

  # Raised when the API key is missing (HTTP 401).
  class AuthenticationError < Error; end

  # Raised when the API key is invalid or quota is exceeded (HTTP 403).
  class ForbiddenError < Error; end

  # Raised for invalid IP addresses or malformed requests (HTTP 400).
  class BadRequestError < Error; end
end
