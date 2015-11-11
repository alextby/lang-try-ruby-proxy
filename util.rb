#!/usr/bin/ruby

#
# Utils module
#
module Utils

  #
  # Extended double-ended queue implementation.
  # Plus to the typical deque API there 2 methods:
  #  - bubble(element)
  #  - drown(element)
  # which allow guaranteed o(1) time for placing an
  # arbitrary element (present) to either head or tail of the deque.
  # Like usually, this deque is powered by a linkedlist + there is
  # a hashtable which keeps an index of all elements faster access.
  # This is slightly more memory-intensive than a typical deque occupies.
  # WARNING: this implementation is NOT thread-safe meaning that the clients
  # have to preserve synchronized access (if necessary).
  #
  class FancyDeque

    # private queue item holder
    Item = Struct.new(:prev, :next, :value)

    # Constructor
    def initialize
      @index = Hash.new
      @head = nil
      @tail = nil
      @size = 0
    end

    # Is Empty ?
    def empty?
      @size == 0
    end

    # Clear
    def clear
      @head = @tail = nil
      @size = 0
    end

    # Size of the queue
    def size
      @size
    end

    #
    # Returns the head element without actually popping it out
    # @return head element
    #
    def head
      @head && @head[:value]
    end

    #
    # Returns the tail element without actually popping it out
    # @return tail element
    #
    def tail
      @tail && @tail[:value]
    end

    #
    # Pushes a new element to the head of the queue
    # @param value
    # @return pushed value
    #
    def push_head(value)
      node = Item.new(nil, nil, value)
      @index[value] = node
      if @head
        node[:next] = @head
        @head[:prev] = node
        @head = node
      else
        @head = @tail = node
      end
      @size += 1
      value
    end

    #
    # Pushes a new element to the tail of the queue
    # @param value
    # @return pushed value
    #
    def push_tail(value)
      node = Item.new(nil, nil, value)
      @index[value] = node
      if @tail
        node[:prev] = @tail
        @tail[:next] = node
        @tail = node
      else
        @head = @tail = node
      end
      @size += 1
      value
    end

    #
    # Pops the head element
    # @return head element
    #
    def pop_head
      return nil unless @head
      node = @head
      @index.delete node[:value]
      if @size == 1
        clear
        return node[:value]
      else
        @head[:next][:prev] = nil
        @head = @head[:next]
      end
      @size -= 1
      node[:value]
    end

    #
    # Pops the tail element
    # @return tail element
    #
    def pop_tail
      return nil unless @tail
      node = @tail
      @index.delete node[:value]
      if @size == 1
        clear
        return node[:value]
      else
        @tail[:prev][:next] = nil
        @tail = @tail[:prev]
      end
      @size -= 1
      node[:value]
    end

    #
    # Pushes the given element (if present) all the way up
    # to the head of the queue
    # @param value
    # @return true/false
    #
    def bubble(value)
      node = @index[value]
      return false if node == nil
      return true if @size == 1
      return true if node == @head
      @index.delete node[:value]
      if node != @tail
        node[:prev][:next] = node[:next]
        node[:next][:prev] = node[:prev]
        @size -= 1
      else
        pop_tail
      end
      push_head node[:value]
      true
    end

    #
    # Pushes the given element (if present) all the way
    # down to the tail of the queue
    # @param value
    # @return true/false
    #
    def drown(value)
      node = @index[value]
      return false if node == nil
      return true if @size == 1
      return true if node == @tail
      @index.delete node[:value]
      if node != @head
        node[:next][:prev] = node[:prev]
        node[:prev][:next] = node[:next]
        @size -= 1
      else
        pop_head
      end
      push_tail node[:value]
      true
    end

    #
    # Head-to-Tail Iterator
    #
    def each
      return unless @head
      node = @head
      while node
        yield node[:value]
        node = node[:next]
      end
    end

    #
    # Tail-to-Head Iterator
    #
    def rev_each
      return unless @tail
      node = @tail
      while node
        yield node[:value]
        node = node[:prev]
      end
    end

  end

  class Logger

    def initialize(verbose = false)
      @verbose = verbose
    end

    def info(msg)
      STDOUT << "thread_#{Thread.current[:id]}: #{msg}\n"
    end

    def debug(msg)
       STDOUT << "thread_#{Thread.current[:id]}: [debug] #{msg}\n" if @verbose
    end

    def error(msg)
      STDERR << "thread_#{Thread.current[:id]}: [ERROR] #{msg}\n"
    end
  end

end


# Demonstration/tests
if $0 == __FILE__

  deque = Utils::FancyDeque.new
  logger = Utils::Logger.new true

  deque.push_tail 1
  deque.push_tail 2
  deque.push_tail 0
  deque.push_head 10
  deque.push_head 4
  deque.push_head 9
  deque.push_head 7

  deque.each { |item| print "#{item}, " }
  puts
  deque.rev_each { |item| print "#{item}, " }

  puts
  (0..1000).each do | |
    val = rand(15)
    puts "#{deque.bubble val}<==#{val}"
    deque.each { |item| print "#{item}, " }
    puts
  end

  puts
  (0..1000).each do | |
    val = rand(15)
    puts "#{deque.drown val}==>#{val}"
    deque.each { |item| print "#{item}, " }
    puts
  end

  puts
  logger.info deque.pop_tail
  logger.info deque.pop_tail
  logger.debug deque.pop_head
  logger.debug deque.pop_head
  logger.debug deque.pop_head

end