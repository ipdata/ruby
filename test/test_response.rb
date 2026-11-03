# frozen_string_literal: true

require_relative "test_helper"

class TestResponse < Minitest::Test
  include IPDataFixtures

  def setup
    @response = IPData::Response.new(SAMPLE_RESPONSE)
  end

  # --- Dot notation access ---

  def test_top_level_string_field
    assert_equal "8.8.8.8", @response.ip
  end

  def test_top_level_boolean_field
    assert_equal false, @response.is_eu
  end

  def test_top_level_numeric_field
    assert_equal 37.386, @response.latitude
    assert_equal(-122.0838, @response.longitude)
  end

  def test_city_and_region
    assert_equal "Mountain View", @response.city
    assert_equal "California", @response.region
    assert_equal "CA", @response.region_code
  end

  def test_country_fields
    assert_equal "United States", @response.country_name
    assert_equal "US", @response.country_code
  end

  def test_continent_fields
    assert_equal "North America", @response.continent_name
    assert_equal "NA", @response.continent_code
  end

  def test_calling_code_and_postal
    assert_equal "1", @response.calling_code
    assert_equal "94035", @response.postal
  end

  def test_flag_fields
    assert_includes @response.flag, "us.png"
    refute_nil @response.emoji_flag
    refute_nil @response.emoji_unicode
  end

  def test_status_and_count
    assert_equal 200, @response.status
    assert_equal "1", @response.count
  end

  # --- Nested object access ---

  def test_asn_nested_object
    asn = @response.asn
    assert_instance_of IPData::Response, asn
    assert_equal "AS15169", asn.asn
    assert_equal "Google LLC", asn.name
    assert_equal "google.com", asn.domain
    assert_equal "8.8.8.0/24", asn.route
    assert_equal "business", asn.type
  end

  def test_company_nested_object
    company = @response.company
    assert_instance_of IPData::Response, company
    assert_equal "Google LLC", company.name
    assert_equal "google.com", company.domain
    assert_equal "8.8.8.0/24", company.network
    assert_equal "business", company.type
  end

  def test_carrier_nested_object
    carrier = @response.carrier
    assert_instance_of IPData::Response, carrier
    assert_equal "", carrier.name
  end

  def test_currency_nested_object
    currency = @response.currency
    assert_instance_of IPData::Response, currency
    assert_equal "US Dollar", currency.name
    assert_equal "USD", currency.code
    assert_equal "$", currency.symbol
    assert_equal "$", currency.native
    assert_equal "US dollars", currency.plural
  end

  def test_time_zone_nested_object
    tz = @response.time_zone
    assert_instance_of IPData::Response, tz
    assert_equal "America/Los_Angeles", tz.name
    assert_equal "PST", tz.abbr
    assert_equal "-0800", tz.offset
    assert_equal false, tz.is_dst
    refute_nil tz.current_time
  end

  def test_threat_nested_object
    threat = @response.threat
    assert_instance_of IPData::Response, threat
    assert_equal false, threat.is_tor
    assert_equal false, threat.is_vpn
    assert_equal false, threat.is_icloud_relay
    assert_equal false, threat.is_proxy
    assert_equal true, threat.is_datacenter
    assert_equal false, threat.is_anonymous
    assert_equal false, threat.is_known_attacker
    assert_equal false, threat.is_known_abuser
    assert_equal false, threat.is_threat
    assert_equal false, threat.is_bogon
  end

  def test_threat_scores
    scores = @response.threat.scores
    assert_instance_of IPData::Response, scores
    assert_equal 0, scores.vpn_score
    assert_equal 0, scores.proxy_score
    assert_equal 0, scores.threat_score
    assert_equal 100, scores.trust_score
  end

  def test_threat_blocklists_array
    blocklists = @response.threat.blocklists
    assert_instance_of Array, blocklists
    assert_empty blocklists
  end

  # --- Languages array ---

  def test_languages_array
    langs = @response.languages
    assert_instance_of Array, langs
    assert_equal 1, langs.size
  end

  def test_languages_array_elements_are_responses
    lang = @response.languages.first
    assert_instance_of IPData::Response, lang
    assert_equal "English", lang.name
    assert_equal "English", lang.native
    assert_equal "en", lang.code
  end

  # --- Hash-style access ---

  def test_string_key_access
    assert_equal "8.8.8.8", @response["ip"]
    assert_equal "Mountain View", @response["city"]
  end

  def test_symbol_key_access
    assert_equal "8.8.8.8", @response[:ip]
    assert_equal "Mountain View", @response[:city]
  end

  # --- Utility methods ---

  def test_to_h_returns_raw_hash
    hash = @response.to_h
    assert_instance_of Hash, hash
    assert_equal "8.8.8.8", hash["ip"]
    assert_equal SAMPLE_RESPONSE, hash
  end

  def test_to_json
    json = @response.to_json
    parsed = JSON.parse(json)
    assert_equal "8.8.8.8", parsed["ip"]
    assert_equal "Mountain View", parsed["city"]
  end

  def test_key?
    assert @response.key?("ip")
    assert @response.key?(:city)
    refute @response.key?("nonexistent")
  end

  def test_each
    keys = []
    @response.each { |k, _v| keys << k }
    assert_includes keys, "ip"
    assert_includes keys, "city"
  end

  def test_equality_with_response
    other = IPData::Response.new(SAMPLE_RESPONSE.dup)
    assert_equal @response, other
  end

  def test_equality_with_hash
    assert_equal @response, SAMPLE_RESPONSE
  end

  def test_inspect
    assert_includes @response.inspect, "IPData::Response"
    assert_includes @response.inspect, "8.8.8.8"
  end

  def test_to_s
    assert_includes @response.to_s, "8.8.8.8"
  end

  # --- method_missing / respond_to_missing? ---

  def test_respond_to_existing_key
    assert_respond_to @response, :ip
    assert_respond_to @response, :city
    assert_respond_to @response, :asn
  end

  def test_respond_to_missing_key
    refute_respond_to @response, :nonexistent_field
  end

  def test_method_missing_raises_for_unknown_key
    assert_raises(NoMethodError) { @response.nonexistent_field }
  end

  # --- is_satellite / is_anycast (sent by the API only when true) ---

  def test_is_satellite_reads_true_when_present
    response = IPData::Response.new(SAMPLE_SATELLITE_RESPONSE)
    assert_equal true, response.is_satellite
    assert_equal true, response["is_satellite"]
    assert response.key?("is_satellite")
  end

  def test_is_anycast_reads_true_when_present
    response = IPData::Response.new(SAMPLE_ANYCAST_RESPONSE)
    assert_equal true, response.is_anycast
    assert_equal true, response[:is_anycast]
    assert response.key?(:is_anycast)
  end

  def test_new_flags_read_false_when_absent
    assert_equal false, @response.is_satellite
    assert_equal false, @response.is_anycast

    assert_equal false, IPData::Response.new(SAMPLE_SATELLITE_RESPONSE).is_anycast
    assert_equal false, IPData::Response.new(SAMPLE_ANYCAST_RESPONSE).is_satellite

    vpn = IPData::Response.new(SAMPLE_VPN_RESPONSE)
    assert_equal false, vpn.is_satellite
    assert_equal false, vpn.is_anycast
  end

  def test_new_flags_leave_the_raw_hash_untouched
    refute @response.key?("is_satellite")
    refute @response.key?("is_anycast")
    assert_nil @response["is_satellite"]
    assert_nil @response[:is_anycast]
    assert_equal SAMPLE_RESPONSE, @response.to_h

    keys = []
    @response.each { |k, _v| keys << k }
    refute_includes keys, "is_satellite"
    refute_includes keys, "is_anycast"
    refute_includes JSON.parse(@response.to_json).keys, "is_satellite"
  end

  def test_new_flags_are_always_responded_to
    assert_respond_to @response, :is_satellite
    assert_respond_to @response, :is_anycast
    assert_respond_to IPData::Response.new(SAMPLE_SATELLITE_RESPONSE), :is_satellite
  end

  def test_satellite_sample_other_fields
    response = IPData::Response.new(SAMPLE_SATELLITE_RESPONSE)
    assert_equal "98.97.34.0", response.ip
    assert_equal false, response.is_eu
    assert_equal "Seattle", response.city
    assert_equal "AS14593", response.asn.asn
    assert_equal "spacex.com", response.asn.domain
    assert_empty response.threat.blocklists
    assert_equal 97, response.threat.scores.trust_score
  end

  def test_anycast_sample_null_fields_pass_through
    response = IPData::Response.new(SAMPLE_ANYCAST_RESPONSE)
    assert_nil response.city
    assert_nil response.region_type
    assert_nil response.time_zone.name
    assert_equal "hosting", response.asn.type
    assert_equal "about.google", response.company.domain
    assert_equal true, response.threat.is_datacenter
  end

  # --- Blocklist entries: first_seen, last_seen, days_seen ---

  def test_blocklist_entries_carry_dates_and_days_seen
    blocklists = IPData::Response.new(SAMPLE_ANYCAST_RESPONSE).threat.blocklists
    assert_equal 2, blocklists.size

    entry = blocklists.first
    assert_instance_of IPData::Response, entry
    assert_equal "ipdata", entry.name
    assert_equal "https://ipdata.co", entry.site
    assert_equal "cloud", entry.type
    assert_equal 1, entry.days_seen
    assert_equal "2026-11-02", entry.first_seen
    assert_equal "2026-11-02", entry.last_seen
    assert_equal "open_resolvers", blocklists.last.type
  end

  def test_blocklist_dates_stay_strings
    entry = IPData::Response.new(SAMPLE_VPN_RESPONSE).threat.blocklists.first
    assert_equal "Gluetun", entry.name
    assert_instance_of String, entry.first_seen
    assert_instance_of String, entry.last_seen
    assert_equal "2026-10-31", entry.first_seen
    assert_equal "2026-11-02", entry.last_seen
    assert_equal "2026-10-31", entry["first_seen"]
    assert_equal 2, entry.days_seen
    assert_kind_of Integer, entry.days_seen
  end

  def test_blocklist_entry_without_dates
    blocklists = IPData::Response.new(SAMPLE_VPN_RESPONSE).threat.blocklists
    assert_equal 6, blocklists.size
    assert_equal 5, blocklists.count { |entry| entry.key?("first_seen") }

    undated = blocklists[2]
    assert_equal "ipdata", undated.name
    assert_equal "https://ipdata.co", undated.site
    assert_equal "vpn", undated.type
    refute undated.key?("first_seen")
    refute undated.key?("last_seen")
    refute undated.key?("days_seen")
    assert_nil undated["first_seen"]
    assert_nil undated["last_seen"]
    assert_nil undated[:days_seen]
    refute_respond_to undated, :first_seen
    assert_equal({ "name" => "ipdata", "site" => "https://ipdata.co", "type" => "vpn" }, undated.to_h)
  end

  def test_vpn_sample_threat_flags
    threat = IPData::Response.new(SAMPLE_VPN_RESPONSE).threat
    assert_equal true, threat.is_vpn
    assert_equal true, threat.is_anonymous
    assert_equal true, threat.is_threat
    assert_equal false, threat.is_tor
    assert_equal 0, threat.scores.trust_score
  end

  # --- Unknown keys ---

  def test_unknown_keys_pass_through
    response = IPData::Response.new(SAMPLE_RESPONSE.merge("some_future_field" => { "x" => 1 }))
    assert_equal 1, response.some_future_field.x
    assert_equal({ "x" => 1 }, response["some_future_field"].to_h)
    assert_equal "8.8.8.8", response.ip
  end

  # --- Edge cases ---

  def test_nil_data
    response = IPData::Response.new(nil)
    assert_equal({}, response.to_h)
  end

  def test_empty_data
    response = IPData::Response.new({})
    assert_equal({}, response.to_h)
  end
end
