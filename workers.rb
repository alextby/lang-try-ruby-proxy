#!/usr/bin/ruby

# requires
require 'thread'

#
# Workers module
#
module Workers

  #
  # A simple and straighforward Thread-pool implementation.
  # The pool keeps a queue of jobs (tasks) and an array of workers (threads).
  # Once there new tasks in the queue they are immidiately picked up by the workers.
  # Each worker is intended to be failure-safe meaning that no matter what happens
  # during the task execution the worker must survive for future assignments.
  # Each worker is thereby stateless towards the task being execution.
  #
  class Pool

    # Constructor
    def initialize(size)
      @size = size
      @jobs = Queue.new
      @pool = Array.new(@size) do |i|
        Thread.new do
          begin
            Thread.current[:id] = i
            catch(:exit) do
              loop do
                job, args = @jobs.pop
                job.call(*args)
              end
            end
          rescue
            # boy, spawing a new thread is too expensive...
            # so get back to work now
            retry
          end
        end
      end
    end

    #
    # Puts a code block with arbitrary arguments
    # to the task queue
    #
    def schedule(*args, &block)
      @jobs << [block, args]
      #alive = 0
      #@pool.each do | t |
      #    alive += 1 if t.alive?
      #end
      #puts "[TPOOL] alive=#{alive}"
    end

    #
    # Gently shuts the pool down
    # by sending signals to each worker allowing them
    # to accomplish their tasks first
    #
    def shutdown
      @size.times do
        schedule { throw :exit }
      end
      @pool.map(&:join)
    end
  end
end


# Demonstration/tests:
if $0 == __FILE__
  p = Workers::Pool.new(10)
  15.times do |i|
    p.schedule do
      #p.schedule do
      #  sleep rand(4) + 2
      for j in 1..1000000
      end
      puts "Job #{i} done by ##{Thread.current[:id]}\n"
    end
  end
  at_exit { p.shutdown }
end