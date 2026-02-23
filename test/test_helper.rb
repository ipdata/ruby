# frozen_string_literal: true

$LOAD_PATH.unshift File.expand_path("../lib", __dir__)
require "ipdata"
require "minitest/autorun"

# Shared test fixtures for the ipdata test suite.
module IPDataFixtures
  SAMPLE_RESPONSE = {
    "ip" => "8.8.8.8",
    "is_eu" => false,
    "city" => "Mountain View",
    "region" => "California",
    "region_code" => "CA",
    "country_name" => "United States",
    "country_code" => "US",
    "continent_name" => "North America",
    "continent_code" => "NA",
    "latitude" => 37.386,
    "longitude" => -122.0838,
    "postal" => "94035",
    "calling_code" => "1",
    "flag" => "https://ipdata.co/flags/us.png",
    "emoji_flag" => "\u{1F1FA}\u{1F1F8}",
    "emoji_unicode" => "U+1F1FA U+1F1F8",
    "asn" => {
      "asn" => "AS15169",
      "name" => "Google LLC",
      "domain" => "google.com",
      "route" => "8.8.8.0/24",
      "type" => "business"
    },
    "company" => {
      "name" => "Google LLC",
      "domain" => "google.com",
      "network" => "8.8.8.0/24",
      "type" => "business"
    },
    "carrier" => {
      "name" => "",
      "mcc" => "",
      "mnc" => ""
    },
    "languages" => [
      { "name" => "English", "native" => "English", "code" => "en" }
    ],
    "currency" => {
      "name" => "US Dollar",
      "code" => "USD",
      "symbol" => "$",
      "native" => "$",
      "plural" => "US dollars"
    },
    "time_zone" => {
      "name" => "America/Los_Angeles",
      "abbr" => "PST",
      "offset" => "-0800",
      "is_dst" => false,
      "current_time" => "2024-01-01T00:00:00-08:00"
    },
    "threat" => {
      "is_tor" => false,
      "is_vpn" => false,
      "is_icloud_relay" => false,
      "is_proxy" => false,
      "is_datacenter" => true,
      "is_anonymous" => false,
      "is_known_attacker" => false,
      "is_known_abuser" => false,
      "is_threat" => false,
      "is_bogon" => false,
      "blocklists" => [],
      "scores" => {
        "vpn_score" => 0,
        "proxy_score" => 0,
        "threat_score" => 0,
        "trust_score" => 100
      }
    },
    "count" => "1",
    "status" => 200
  }.freeze

  SAMPLE_BULK_RESPONSE = [
    SAMPLE_RESPONSE,
    SAMPLE_RESPONSE.merge("ip" => "1.1.1.1", "city" => "Los Angeles", "country_name" => "Australia")
  ].freeze

  # Helper to create a stubbed Net::HTTP response.
  def stub_http_response(status: "200", body: nil)
    response = Net::HTTPResponse.allocate
    response.instance_variable_set(:@code, status)
    response.instance_variable_set(:@body, body || JSON.generate(SAMPLE_RESPONSE))
    response.instance_variable_set(:@read, true)

    # Define response class checking
    case status.to_i
    when 200..299
      def response.is_a?(klass)
        klass == Net::HTTPSuccess ? true : super
      end
    else
      def response.is_a?(klass)
        klass == Net::HTTPSuccess ? false : super
      end
    end

    def response.body
      @body
    end

    def response.code
      @code
    end

    response
  end
end
