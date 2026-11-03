# IPData Ruby SDK

Official Ruby client for the [ipdata.co](https://ipdata.co) IP geolocation API. Look up geolocation, threat intelligence, ASN, company, carrier, currency, timezone, and language data for any IP address.

## Installation

Add to your Gemfile:

```ruby
gem "ipdata"
```

Then run:

```sh
bundle install
```

Or install directly:

```sh
gem install ipdata
```

## Quick Start

Get a free API key at [ipdata.co/sign-up](https://ipdata.co/sign-up.html) (1,500 requests/day).

```ruby
require "ipdata"

client = IPData::Client.new("YOUR_API_KEY")

# Look up an IP address
response = client.lookup("8.8.8.8")

response.ip           # => "8.8.8.8"
response.city         # => "Mountain View"
response.country_name # => "United States"
response.latitude     # => 37.386
response.longitude    # => -122.0838
```

## Usage

### Look Up Your Own IP

```ruby
response = client.lookup
response.ip # => your public IP
```

### Look Up a Specific IP

```ruby
response = client.lookup("1.1.1.1")
response.country_name # => "Australia"
response.asn.name     # => "Cloudflare, Inc."
response.asn.asn      # => "AS13335"
```

### Select Specific Fields

Reduce payload by requesting only the fields you need:

```ruby
response = client.lookup("8.8.8.8", fields: ["ip", "city", "country_name"])
response.city # => "Mountain View"
```

### Extract a Single Field

```ruby
city = client.lookup("8.8.8.8", select_field: "city")
# => "Mountain View"
```

### Bulk Lookup

Look up multiple IPs in a single request (max 100):

```ruby
responses = client.bulk_lookup(["8.8.8.8", "1.1.1.1"])
responses.each do |r|
  puts "#{r.ip}: #{r.country_name}"
end
```

Bulk lookup also supports field filtering:

```ruby
responses = client.bulk_lookup(
  ["8.8.8.8", "1.1.1.1"],
  fields: ["ip", "country_name", "city"]
)
```

### EU Endpoint (GDPR Compliant)

Route requests through EU data centers only:

```ruby
client = IPData::Client.eu("YOUR_API_KEY")
```

### Caching

Enable an in-memory LRU cache to reduce API calls:

```ruby
cache = IPData::Cache.new(max_size: 1024, ttl: 3600) # 1h TTL
client = IPData::Client.new("YOUR_API_KEY", cache: cache)

client.lookup("8.8.8.8") # hits API
client.lookup("8.8.8.8") # served from cache
```

### Custom Timeout

```ruby
client = IPData::Client.new("YOUR_API_KEY", timeout: 10) # 10 seconds to connect, read and write
```

## Connection reuse

An `IPData::Client` keeps one persistent HTTPS connection (HTTP/1.1 keep-alive) for as long as it lives. Create one client per process (or one per API key or endpoint), keep it, and reuse it for every lookup: each new client pays a fresh TLS handshake. HTTP/2 is not available with Ruby's `Net::HTTP`, so the saving is the TLS handshake, not multiplexing.

A client is safe to share between threads, but it serialises requests on its single connection, so use one client per thread when you need lookups to run in parallel. Create clients after forking (for example in your web server's after-fork hook): a client inherited from the parent process notices the new process id and opens its own connection instead of reusing the parent's socket, which it never closes. Call `close` at shutdown to finish the connection; the client stays usable and reconnects on the next request.

```ruby
client = IPData::Client.new("YOUR_API_KEY")

client.lookup("8.8.8.8") # opens the connection (TCP + TLS handshake)
client.lookup("1.1.1.1") # reuses it

at_exit { client.close }
```

The connection is opened on the first request. An idle connection is kept for `keep_alive_timeout:` seconds (default 60); after that the next request opens a new one. `timeout:` applies to connecting, reading and writing.

```ruby
client = IPData::Client.new("YOUR_API_KEY", keep_alive_timeout: 30)
```

If the server has silently dropped an idle connection, `lookup` (a `GET`) is retried once by `Net::HTTP` and `bulk_lookup` (a `POST`) once by the client, in both cases on a fresh connection and only when the failure happened before any response byte arrived. Nothing is retried on an HTTP error status.

## Response Fields

All responses are wrapped in `IPData::Response` objects that support both dot-notation and hash-style access:

```ruby
response = client.lookup("8.8.8.8")

# Dot notation
response.ip
response.city
response.region
response.country_name
response.country_code
response.continent_name
response.latitude
response.longitude
response.is_eu
response.is_satellite # satellite ISP; sent only when true, reads false otherwise
response.is_anycast   # anycast address; sent only when true, reads false otherwise
response.postal
response.calling_code
response.flag
response.emoji_flag
response.emoji_unicode

# Nested objects
response.asn.asn          # => "AS15169"
response.asn.name         # => "Google LLC"
response.asn.domain       # => "google.com"
response.asn.route        # => "8.8.8.0/24"
response.asn.type         # => "business"

response.company.name
response.company.domain
response.company.network
response.company.type

response.carrier.name
response.carrier.mcc
response.carrier.mnc

response.currency.name
response.currency.code
response.currency.symbol
response.currency.native
response.currency.plural

response.time_zone.name
response.time_zone.abbr
response.time_zone.offset
response.time_zone.is_dst
response.time_zone.current_time

response.threat.is_tor
response.threat.is_vpn
response.threat.is_icloud_relay
response.threat.is_proxy
response.threat.is_datacenter
response.threat.is_anonymous
response.threat.is_known_attacker
response.threat.is_known_abuser
response.threat.is_threat
response.threat.is_bogon
response.threat.blocklists                  # array of entries: name, site, type and, when the feed reports them:
response.threat.blocklists.first.first_seen # first day listed, "YYYY-MM-DD" (UTC); absent for some feeds
response.threat.blocklists.first.last_seen  # last day listed, "YYYY-MM-DD" (UTC); absent for some feeds
response.threat.blocklists.first.days_seen  # number of days listed (integer); absent for some feeds
response.threat.scores

# Languages (array)
response.languages.first.name
response.languages.first.native
response.languages.first.code

# Hash-style access
response["city"]
response[:country_code]

# Raw hash
response.to_h
```

`is_satellite` and `is_anycast` are included in the API response only when they are true. `response.is_satellite` and `response.is_anycast` read `false` when the key is absent, while `response["is_satellite"]`, `response.key?("is_satellite")` and `response.to_h` reflect the raw response (`nil`, `false` and no key). Each `threat.blocklists` entry carries `first_seen` and `last_seen` (calendar dates as `"YYYY-MM-DD"` strings, UTC) and `days_seen` (an integer) when the feed reports them; some feeds, for example ipdata's own vpn feed, omit all three, so read them with `entry["first_seen"]` (`nil` when absent) or check `entry.key?("first_seen")`. The dates are kept as strings; use `Date.iso8601(entry.first_seen)` if you need `Date` objects.

## Error Handling

```ruby
begin
  client.lookup("8.8.8.8")
rescue IPData::AuthenticationError => e
  # Missing API key (401)
  puts "Auth error: #{e.message} (#{e.status_code})"
rescue IPData::ForbiddenError => e
  # Invalid key or quota exceeded (403)
  puts "Forbidden: #{e.message} (#{e.status_code})"
rescue IPData::BadRequestError => e
  # Invalid IP or bad request (400)
  puts "Bad request: #{e.message} (#{e.status_code})"
rescue IPData::Error => e
  # Any other API error
  puts "Error: #{e.message} (#{e.status_code})"
end
```

## Requirements

- Ruby >= 3.0
- No runtime dependencies (uses only Ruby stdlib)

## Development

```sh
bundle install
bundle exec rake test
```

## License

[MIT](LICENSE)
