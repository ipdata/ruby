# frozen_string_literal: true

require_relative "lib/ipdata/version"

Gem::Specification.new do |spec|
  spec.name          = "ipdata"
  spec.version       = IPData::VERSION
  spec.authors       = ["IPData"]
  spec.email         = ["support@ipdata.co"]

  spec.summary       = "Ruby client for the ipdata IP geolocation API"
  spec.description   = "Official Ruby SDK for the ipdata.co API. " \
                        "Look up geolocation, threat intelligence, ASN, company, " \
                        "carrier, currency, timezone and language data for any IP address."
  spec.homepage      = "https://github.com/ipdata/ruby"
  spec.license       = "MIT"

  spec.required_ruby_version = ">= 3.0"

  spec.metadata = {
    "homepage_uri" => spec.homepage,
    "source_code_uri" => "https://github.com/ipdata/ruby",
    "changelog_uri" => "https://github.com/ipdata/ruby/blob/main/CHANGELOG.md",
    "bug_tracker_uri" => "https://github.com/ipdata/ruby/issues",
    "documentation_uri" => "https://docs.ipdata.co"
  }

  spec.files = Dir["lib/**/*.rb", "LICENSE", "README.md"]
  spec.require_paths = ["lib"]

  # Zero runtime dependencies — uses only Ruby stdlib (net/http, json, uri, monitor)
end
