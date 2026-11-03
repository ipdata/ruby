# Change Log

## 0.2.0

### Added

- Connection reuse: an `IPData::Client` keeps one persistent HTTPS connection (HTTP/1.1 keep-alive) for its lifetime instead of opening a new TLS connection for every request. Create one client and reuse it. New option `keep_alive_timeout:` (seconds, default 60) for the client-side idle timeout, and new method `Client#close` to finish the connection at shutdown; the client reconnects on demand. A client is safe to share between threads (requests are serialised on its connection) and reconnects in a forked child without closing the parent's socket.
- `Response#is_satellite` and `Response#is_anycast`: the API sends these top-level booleans only when they are true; the readers return `false` when the key is absent, while `response["is_satellite"]`, `key?` and `to_h` reflect the raw response. Both names can be requested through `fields:` and `select_field:`.
- `threat.blocklists` entries carry `first_seen`, `last_seen` (`"YYYY-MM-DD"`, UTC) and `days_seen` when the feed reports them; some feeds omit all three.

### Changed

- `timeout:` now also applies to writes (previously only to connecting and reading).
- `bulk_lookup` (`POST /bulk`) is retried once, on a fresh connection, when a reused connection died before any response byte arrived; `lookup` (`GET`) was already retried once by `Net::HTTP`. Nothing is retried on an HTTP error status.
- The `User-Agent` header is now `ipdata-ruby/<version> Ruby/<ruby-version> (<platform>)` instead of `ruby-ipdata/...`.
- Gem metadata: the homepage is now https://ipdata.co; `source_code_uri` keeps pointing at this repository.

### Fixed

- `use_ssl` follows the scheme of `base_url:`, so plain `http://` base URLs work; it used to be always on.
- `lookup(select_field: "city")` without an IP address requests `/city` instead of `//city`.
- A `base_url:` with a path prefix (for example `https://example.com/ipdata`) keeps that prefix in front of every request path instead of losing it.

## 0.1.5

Initial release on RubyGems: `lookup` for the caller's own IP or a given IP with `fields:` and `select_field:`, `bulk_lookup` for up to 100 addresses, `Client.eu` for the EU endpoint, an in-memory LRU cache with TTL, typed errors (`AuthenticationError`, `ForbiddenError`, `BadRequestError`) and no runtime dependencies.
