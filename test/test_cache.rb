# frozen_string_literal: true

require_relative "test_helper"

class TestCache < Minitest::Test
  def setup
    @cache = IPData::Cache.new(max_size: 3, ttl: 60)
  end

  def test_get_returns_nil_for_missing_key
    assert_nil @cache.get("missing")
  end

  def test_set_and_get
    @cache.set("8.8.8.8", "data")
    assert_equal "data", @cache.get("8.8.8.8")
  end

  def test_size
    assert_equal 0, @cache.size
    @cache.set("a", 1)
    assert_equal 1, @cache.size
    @cache.set("b", 2)
    assert_equal 2, @cache.size
  end

  def test_clear
    @cache.set("a", 1)
    @cache.set("b", 2)
    @cache.clear
    assert_equal 0, @cache.size
    assert_nil @cache.get("a")
  end

  def test_overwrite_existing_key
    @cache.set("key", "old")
    @cache.set("key", "new")
    assert_equal "new", @cache.get("key")
    assert_equal 1, @cache.size
  end

  def test_lru_eviction
    @cache.set("a", 1)
    @cache.set("b", 2)
    @cache.set("c", 3)
    # Cache is full (max_size=3). Adding "d" should evict "a" (LRU).
    @cache.set("d", 4)
    assert_nil @cache.get("a")
    assert_equal 2, @cache.get("b")
    assert_equal 3, @cache.get("c")
    assert_equal 4, @cache.get("d")
    assert_equal 3, @cache.size
  end

  def test_lru_access_refreshes_order
    @cache.set("a", 1)
    @cache.set("b", 2)
    @cache.set("c", 3)
    # Access "a" to make it most recently used
    @cache.get("a")
    # Adding "d" should now evict "b" (least recently used)
    @cache.set("d", 4)
    assert_equal 1, @cache.get("a")
    assert_nil @cache.get("b")
    assert_equal 3, @cache.get("c")
    assert_equal 4, @cache.get("d")
  end

  def test_ttl_expiration
    cache = IPData::Cache.new(max_size: 10, ttl: 0) # 0 second TTL
    cache.set("key", "value")
    sleep 0.01 # Ensure time has passed
    assert_nil cache.get("key")
  end

  def test_stores_complex_objects
    response = IPData::Response.new("ip" => "8.8.8.8", "city" => "Mountain View")
    @cache.set("8.8.8.8", response)
    cached = @cache.get("8.8.8.8")
    assert_instance_of IPData::Response, cached
    assert_equal "Mountain View", cached.city
  end

  def test_default_configuration
    cache = IPData::Cache.new
    assert_equal 0, cache.size
    # Should be able to store many entries
    100.times { |i| cache.set("key#{i}", i) }
    assert_equal 100, cache.size
  end

  def test_thread_safety
    cache = IPData::Cache.new(max_size: 1000, ttl: 60)
    threads = 10.times.map do |t|
      Thread.new do
        100.times do |i|
          cache.set("t#{t}_k#{i}", "v#{i}")
          cache.get("t#{t}_k#{i}")
        end
      end
    end
    threads.each(&:join)
    # No exceptions raised — thread safety verified
    assert cache.size <= 1000
  end
end
