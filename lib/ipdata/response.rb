# frozen_string_literal: true

require "json"

module IPData
  # Lightweight wrapper around the parsed API JSON response.
  #
  # Provides both dot-notation and hash-style access:
  #   response.city          # => "Mountain View"
  #   response["city"]       # => "Mountain View"
  #   response[:city]        # => "Mountain View"
  #   response.asn.name      # => "Google LLC"
  #   response.threat.is_vpn # => false
  #
  # Nested hashes are recursively wrapped as Response objects.
  # Arrays of hashes (e.g. languages, blocklists) are mapped to Response arrays.
  class Response
    def initialize(data)
      @data = data || {}
    end

    # Hash-style access. Accepts string or symbol keys.
    def [](key)
      wrap(@data[key.to_s])
    end

    # Returns the underlying raw Hash.
    def to_h
      @data
    end

    # Serialize back to JSON.
    def to_json(*)
      JSON.generate(@data)
    end

    def to_s
      @data.to_s
    end

    def inspect
      "#<#{self.class} #{@data.inspect}>"
    end

    # Returns true if the key exists in the response data.
    def key?(key)
      @data.key?(key.to_s)
    end

    # Iterate over key-value pairs.
    def each(&block)
      @data.each(&block)
    end

    def ==(other)
      case other
      when Response then @data == other.to_h
      when Hash then @data == other
      else false
      end
    end

    private

    def wrap(value)
      case value
      when Hash then Response.new(value)
      when Array then value.map { |v| wrap(v) }
      else value
      end
    end

    def method_missing(name, *args)
      key = name.to_s
      if @data.key?(key)
        wrap(@data[key])
      else
        super
      end
    end

    def respond_to_missing?(name, include_private = false)
      @data.key?(name.to_s) || super
    end
  end
end
