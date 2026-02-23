# frozen_string_literal: true

require "monitor"

module IPData
  # Thread-safe LRU cache with TTL expiration.
  #
  # Used to cache IP lookup results and avoid redundant API calls.
  # Uses Ruby's stdlib Monitor for thread safety.
  #
  # @example
  #   cache = IPData::Cache.new(max_size: 1024, ttl: 3600)
  #   client = IPData::Client.new("KEY", cache: cache)
  class Cache
    Entry = Struct.new(:value, :expires_at)

    DEFAULT_MAX_SIZE = 4096
    DEFAULT_TTL = 86_400 # 24 hours

    def initialize(max_size: DEFAULT_MAX_SIZE, ttl: DEFAULT_TTL)
      @max_size = max_size
      @ttl = ttl
      @store = {}
      @monitor = Monitor.new
    end

    # Retrieve a cached value. Returns nil if missing or expired.
    def get(key)
      @monitor.synchronize do
        entry = @store[key]
        return nil unless entry

        if Time.now > entry.expires_at
          @store.delete(key)
          return nil
        end

        # Move to end (most recently used) by re-inserting
        @store.delete(key)
        @store[key] = entry
        entry.value
      end
    end

    # Store a value in the cache. Evicts the least recently used entry
    # if the cache is at capacity.
    def set(key, value)
      @monitor.synchronize do
        @store.delete(key) # remove if exists (re-insert at end)

        # Evict LRU entry if at capacity
        if @store.size >= @max_size
          lru_key = @store.keys.first
          @store.delete(lru_key)
        end

        @store[key] = Entry.new(value, Time.now + @ttl)
      end
    end

    # Remove all entries.
    def clear
      @monitor.synchronize { @store.clear }
    end

    # Number of entries currently cached.
    def size
      @monitor.synchronize { @store.size }
    end
  end
end
