# frozen_string_literal: true

begin
  require "dalli"
rescue LoadError => e
  $stderr.puts "You don't have dalli installed in your application. Please add it to your Gemfile and run bundle install"
  raise e
end

require "active_support/core_ext/enumerable"
require "active_support/core_ext/marshal"
require "active_support/core_ext/array/extract_options"

module ActiveSupport
  module Cache
    # A cache store implementation which stores data in Memcached:
    # https://memcached.org
    #
    # This is currently the most popular cache store for production websites.
    #
    # Special features:
    # - Clustering and load balancing. One can specify multiple memcached servers,
    #   and MemCacheStore will load balance between all available servers. If a
    #   server goes down, then MemCacheStore will ignore it until it comes back up.
    #
    # MemCacheStore implements the Strategy::LocalCache strategy which implements
    # an in-memory cache inside of a block.
    class MemCacheStore < Store
      DEFAULT_CODER = NullCoder # Dalli automatically Marshal values

      # Provide support for raw values in the local cache strategy.
      module LocalCacheWithRaw # :nodoc:
        private
          def write_entry(key, entry, **options)
            if options[:raw] && local_cache
              raw_entry = Entry.new(entry.value.to_s)
              raw_entry.expires_at = entry.expires_at
              super(key, raw_entry, **options)
            else
              super
            end
          end
      end

      # Advertise cache versioning support.
      def self.supports_cache_versioning?
        true
      end

      prepend Strategy::LocalCache
      prepend LocalCacheWithRaw

      ESCAPE_KEY_CHARS = /[\x00-\x20%\x7F-\xFF]/n

      # Creates a new Dalli::Client instance with specified addresses and options.
      # If no addresses are provided, we give nil to Dalli::Client, so it uses its fallbacks:
      # - ENV["MEMCACHE_SERVERS"] (if defined)
      # - "127.0.0.1:11211"        (otherwise)
      #
      #   ActiveSupport::Cache::MemCacheStore.build_mem_cache
      #     # => #<Dalli::Client:0x007f98a47d2028 @servers=["127.0.0.1:11211"], @options={}, @ring=nil>
      #   ActiveSupport::Cache::MemCacheStore.build_mem_cache('localhost:10290')
      #     # => #<Dalli::Client:0x007f98a47b3a60 @servers=["localhost:10290"], @options={}, @ring=nil>
      def self.build_mem_cache(*addresses) # :nodoc:
        addresses = addresses.flatten
        options = addresses.extract_options!
        addresses = nil if addresses.compact.empty?
        pool_options = retrieve_pool_options(options)

        if pool_options.empty?
          Dalli::Client.new(addresses, options)
        else
          ensure_connection_pool_added!
          ConnectionPool.new(pool_options) { Dalli::Client.new(addresses, options.merge(threadsafe: false)) }
        end
      end

      # Creates a new MemCacheStore object, with the given memcached server
      # addresses. Each address is either a host name, or a host-with-port string
      # in the form of "host_name:port". For example:
      #
      #   ActiveSupport::Cache::MemCacheStore.new("localhost", "server-downstairs.localnetwork:8229")
      #
      # If no addresses are provided, but ENV['MEMCACHE_SERVERS'] is defined, it will be used instead. Otherwise,
      # MemCacheStore will connect to localhost:11211 (the default memcached port).
      def initialize(*addresses)
        addresses = addresses.flatten
        options = addresses.extract_options!
        super(options)

        unless [String, Dalli::Client, NilClass].include?(addresses.first.class)
          raise ArgumentError, "First argument must be an empty array, an array of hosts or a Dalli::Client instance."
        end
        if addresses.first.is_a?(Dalli::Client)
          @data = addresses.first
        else
          mem_cache_options = options.dup
          UNIVERSAL_OPTIONS.each { |name| mem_cache_options.delete(name) }
          @data = self.class.build_mem_cache(*(addresses + [mem_cache_options]))
        end
      end

      # Increment a cached value. This method uses the memcached incr atomic
      # operator and can only be used on values written with the :raw option.
      # Calling it on a value not stored with :raw will initialize that value
      # to zero.
      def increment(name, amount = 1, options = nil)
        options = merged_options(options)
        instrument(:increment, name, amount: amount) do
          rescue_error_with nil do
            @data.with { |c| c.incr(normalize_key(name, options), amount, options[:expires_in]) }
          end
        end
      end

      # Decrement a cached value. This method uses the memcached decr atomic
      # operator and can only be used on values written with the :raw option.
      # Calling it on a value not stored with :raw will initialize that value
      # to zero.
      def decrement(name, amount = 1, options = nil)
        options = merged_options(options)
        instrument(:decrement, name, amount: amount) do
          rescue_error_with nil do
            @data.with { |c| c.decr(normalize_key(name, options), amount, options[:expires_in]) }
          end
        end
      end

      # Clear the entire cache on all memcached servers. This method should
      # be used with care when shared cache is being used.
      def clear(options = nil)
        rescue_error_with(nil) { @data.with { |c| c.flush_all } }
      end

      # Get the statistics from the memcached servers.
      def stats
        @data.with { |c| c.stats }
      end

      private
        # Read an entry from the cache.
        def read_entry(key, **options)
          rescue_error_with(nil) { deserialize_entry(@data.with { |c| c.get(key, options) }) }
        end

        # Write an entry to the cache.
        def write_entry(key, entry, **options)
          method = options[:unless_exist] ? :add : :set
          value = options[:raw] ? entry.value.to_s : serialize_entry(entry)
          expires_in = options[:expires_in].to_i
          if options[:race_condition_ttl] && expires_in > 0 && !options[:raw]
            # Set the memcache expire a few minutes in the future to support race condition ttls on read
            expires_in += 5.minutes
          end
          rescue_error_with false do
            # The value "compress: false" prevents duplicate compression within Dalli.
            @data.with { |c| c.send(method, key, value, expires_in, **options, compress: false) }
          end
        end

        # Reads multiple entries from the cache implementation.
        def read_multi_entries(names, **options)
          keys_to_names = names.index_by { |name| normalize_key(name, options) }

          raw_values = @data.with { |c| c.get_multi(keys_to_names.keys) }
          values = {}

          raw_values.each do |key, value|
            entry = deserialize_entry(value)

            unless entry.expired? || entry.mismatched?(normalize_version(keys_to_names[key], options))
              values[keys_to_names[key]] = entry.value
            end
          end

          values
        end

        # Delete an entry from the cache.
        def delete_entry(key, **options)
          rescue_error_with(false) { @data.with { |c| c.delete(key) } }
        end

        # Memcache keys are binaries. So we need to force their encoding to binary
        # before applying the regular expression to ensure we are escaping all
        # characters properly.
        def normalize_key(key, options)
          key = super

          if key
            key = key.dup.force_encoding(Encoding::ASCII_8BIT)
            key = key.gsub(ESCAPE_KEY_CHARS) { |match| "%#{match.getbyte(0).to_s(16).upcase}" }
            key = "#{key[0, 213]}:md5:#{ActiveSupport::Digest.hexdigest(key)}" if key.size > 250
          end

          key
        end

        def deserialize_entry(payload)
          entry = super
          entry = Entry.new(entry, compress: false) unless entry.nil? || entry.is_a?(Entry)
          entry
        end

        def rescue_error_with(fallback)
          yield
        rescue Dalli::DalliError => e
          logger.error("DalliError (#{e}): #{e.message}") if logger
          fallback
        end
    end
  end
end
