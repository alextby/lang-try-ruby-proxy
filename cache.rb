#!/usr/bin/ruby

# requires
require './util'

#
# Caching module
#
module Cache

  # Constants
  DEFAULT_ITEM_SIZE = 1_000_000
  DEFAULT_TOTAL_SIZE = 5_000_000

  #
  # Basic in-memory "Least Recently Used" (LRU) algorithm implementation.
  # The storage engine keeps track of the cache objects usage history:
  # the least recently used elements are kept in the end of the internal queue
  # while the most recetly used ones allways bubble up to the head of the queue.
  # Once there is no more room for placing a new object the engine starts rejecting
  # the least recently used elements one-by-one (cache compaction) until there is
  # enough room for the new object.
  # Both get() and put() methods are thread-safe.
  #
  class LRU

    # Internal cache object holder struct
    Item = Struct.new(:data, :size, :when)
    #
    # Creates a new instance.
    # Raises an error if item_size >= total_size.
    # @param item_size - max size of a cache item
    # @param total_size - max total size of the cache
    # The item_size may not bigger than total_size otherwise an exception
    # is thrown
    #
    def initialize(item_size, total_size)
      # statistics
      @total_hits = 0
      @success_hits = 0
      # synch
      @mutex = Mutex.new
      # params
      if item_size > total_size
        raise 'Wrong cache parameters'
      end
      @max_item_s = item_size
      @max_total_s = total_size
      # storage
      @index = Hash.new
      @history = Utils::FancyDeque.new
      # logger
      @logger = Utils::Logger.new VERBOSE
    end

    #
    # Returns either the hit or nil if not found or empty key
    # @param key - cache key
    #
    def get(key)
      return nil if not key
      # the entire block works synchronized
      @mutex.synchronize do
        @total_hits += 1
        return nil unless @index.has_key? key
        unless @history.bubble key
          # must never happen
          @logger.error "[WARN]: the cache failed updating the usage index for #{key}"
        end
        @success_hits += 1
        # make sure
        @history.bubble key
        @logger.debug "(cache$) << #{key}"
        @index[key].data
      end
    end

    #
    # Puts a new cache object
    # Empty and too large objects are rejected (return false)
    # @param key - key
    # @param value - data
    # @returns true/false
    #
    def put(key, value)
      return false unless key && value
      bsize = value.bytesize
      return false unless bsize <= @max_item_s && bsize > 0
      # start of mutex: mission-critical part
      @mutex.synchronize do
        item = Item.new value, bsize, Time.now
        total = size
        if total + bsize <= @max_total_s
          # easy, new item just fits
          accept key, item
        else
          # no room - need to cleanup a bit
          @logger.debug '(cache$) ~~~ begin'
          hlength = @history.size
          hindex = 0
          tsize = total
          while hindex < hlength
            lru_item = @history.pop_tail
            item = @index[lru_item]
            @logger.debug "(cache$) [x] #{lru_item} (#{item.size}b)"
            lru_size = item.size
            @index.delete lru_item
            tsize -= lru_size
            if tsize + bsize <= @max_total_s
              @logger.debug '(cache$) ~~~ end'
              break
            end
            hindex += 1
          end

          accept key, item
        end
      end # end of mutex
      true
    end

    #
    # Returns statistics (current) for the case [i, j, k, l]:
    #  i - number of successes
    #  j - total count of attempts
    #  k - current length of the cache (n of items)
    #  l - current size of the cache (in bytes)
    #
    def stats
      [@success_hits, @total_hits, @index.size, size]
    end

    # ===> Private methods
    private

    #
    # (Re)calculates the total current size of the cache (in bytes)
    #
    def size
        total = 0
        @index.each_value do |v|
          total += v.size
        end
        total
    end

    #
    # Newly puts or updates a cached object.
    # Either case leads to bubbling up this item to
    # the MRU section of the history queue
    # @param key
    # @param item
    #
    def accept(key, item)
      if @index.has_key? key
        # need an update
        @index.store key, item
        @history.bubble key
        @logger.debug "(cache$) [u] #{key}"
      else
        # this is a new insertion
        @index.store key, item
        @history.push_head key
        @logger.debug "(cache$) [i] #{key} (#{item.size}b)"
      end
    end
  end
end


# Demonstration/tests:
if $0 == __FILE__

  VERBOSE = true

  cache = Cache::LRU.new 10, 500

  # randomly fill in the cache

  (1..200).each do |i|
    value = '1'
    r = rand(10)
    (1..r).each do
      value += '1'
    end
    cache.put "/url?sample=#{rand(200)}", value
  end

  t1 = Thread.new do
    (1..1000).each do |i|
      value = '1'
      r = rand(10)
      (1..r).each do
        value += '1'
      end
      cache.put "/url?sample=#{rand(1000)}", value
    end
  end

  # emulate random cache queries
  t2 = Thread.new do
    (1..1000).each do | |
      cache.get "/url?sample=#{rand(1000)}"
    end
  end

  t1.join
  t2.join

  stats = cache.stats
  puts "#{stats[0]}/#{stats[1]} in #{stats[2]}(#{stats[3]}b)"

end