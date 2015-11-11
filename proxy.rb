#!/usr/bin/ruby

# requires
require 'net/http'
require 'socket'
require 'thread'
require 'openssl'

require './workers'
require './cache'
require './util'

#
# Proxy module
#
module Proxy

  #
  # A lightweight HTTP proxy implementation.
  # Currently supports:
  #   - GET
  #   - LRU caching
  #   - Concurrency (+ true parallelism if run with jRuby)
  #
  class HTTP

    # Constants
    BUFFER_SIZE = 4096
    TIMEOUT = 10

    # HTTP constants
    DEFAULT_PORT= 80
    DEFAULT_SCHEME = 'http'
    DEFAULT_SECURE_PORT = 443
    DEFAULT_SECURE_SCHEME = 'https'
    VERB_CONNECT = 'CONNECT'
    VERB_GET = 'GET'

    #
    # Constructor
    # @param port - tcp_proxy listen port
    # @param num_workers - worker pool size
    # @param cached - do we cache ?
    #
    def initialize (port = 8992, num_workers = 50, cached = true)
      @clients = Array::new
      @port = port
      @workers = Workers::Pool.new num_workers
      @logger = Utils::Logger.new VERBOSE

      @cache = Cache::LRU.new Cache::DEFAULT_ITEM_SIZE, Cache::DEFAULT_TOTAL_SIZE
      @cached = cached
      @cache_excludes = %w(.asp .aspx .jsp jspa .jspx .pl .cgi .action .do .php)
    end

    #
    # Creates the server socket and starts the connections
    # dispatcher thread.
    #
    def listen
      begin
        @srvsock = TCPServer.new nil, @port
        @srvsock.setsockopt(Socket::SOL_SOCKET, Socket::SO_REUSEADDR, 1)
        @clients.push(@srvsock)
        @dthread = Thread.new do
          Thread.current[:id] = 'd'
          @logger.info '[PROXY]: Started'
          loop do
            res = IO.select([@srvsock], nil, nil, nil)
            if res != nil then
              res[0].each { |socket|
                if socket == @srvsock then
                  accept
                end
              }
            end
          end
        end
        # wait for the dispatcher thread to quit
        @dthread.join
      rescue Interrupt
        # flow interruption
        @logger.error '[PROXY] Dispatcher thread interrupted'
      rescue => e
        # unexpected error
        @logger.error "Unexpected error: #{e.inspect}"
      ensure
        # cleanup/close resources
        if @srvsock
          @srvsock.close
          @logger.info '[PROXY]: Terminated'
        end
        @clients.each do |sock|
          sock.close unless not sock
        end
        @clients.clear
        @workers.shutdown
      end
    end

    #
    # ===> Private methods
    #
    private

    #
    # Accepts an incoming client connection
    # and submits it for further handling
    #
    def accept
      socket = @srvsock.accept
      @clients << socket
      @workers.schedule do
        # handle current client
        begin
          if socket.eof?
            # client disconnected
            socket.close
            @clients.delete(socket)
          else
            # proxying
            handle socket
          end
        rescue => e
          @logger.error "Unexpected error: #{e.inspect}"
        ensure
          # cleanup
          @clients.delete(socket)
          socket.close
        end
      end
    end

    #
    # Fully handles the proxy chain (source - target - source):
    # - reads/parses the incoming source request
    # - delegates the request to the target
    # - reads response from the target and sends it back to the source
    # - hits the cache if caching is ON
    #
    def handle(source)
      begin
        # parse the request line
        # extract the params of the target
        req = source.readline
        req_s = req.strip
        req_split = parse_req(req_s)
        return if req_split.size < 6
        verb = req_split[0]
        scheme = req_split[2]
        url = req_split[1]
        host = req_split[3]
        port = req_split[4]
        path = req_split[5]

        if verb != VERB_GET
          # this is https
          # not currently supported
          return
        end

        @logger.info "[PROXY] #{req_split[6].strip}"
        # try the cache
        if @cached
          cached = @cache.get url
          if cached && cacheable?(verb, path)
            source.write cached
            source.flush
            @logger.info "<< (cache$) #{url}"
            print_cash_stats
            return
          end
        end

        # establish the proxy connection
        target = tcp_proxy scheme, host, port
        # put the original request line
        target.write req

        response = ''
        while true
          # asynch reading
          selected = IO.select([source, target])
          begin
            selected[0].each do |socket|
              data = socket.readpartial BUFFER_SIZE
              if socket == source
                #@logger.debug ">> #{data.size}b"
                target.write data
                target.flush
              else
                source.write data
                response += data
                source.flush
              end
            end
          rescue EOFError => e
            # response from target done
            @logger.debug "<< #{response.bytesize}b (#{req_s})"
            if @cached && cacheable?(verb, path) && @cache.put(url, response)
              # try caching
              @logger.info ">> (cache$) #{url}"
              print_cash_stats
            end
            break
          end
        end
      rescue => e
        @logger.error "#{e.inspect}"
      ensure
        target.close if target
      end
    end

    #
    # Defines whether the given url is cacheable.
    # Normally we wanna cache static resources mostly (in contrast to the dynamic pages)
    #
    def cacheable?(method, path)
      return false if not path
      # we only accept GETs to be cached
      return false if not method || method != VERB_GET
      @cache_excludes.each do | ext |
        return false unless not path.to_s.strip.include? ext
      end
      true
    end

    def cache_off(source)
      source.write 'Cache-control: no cache\r\n'
      source.write 'Cache-control: no store\r\n'
      source.write 'Pragma: no-cache\r\n'
      source.write 'Expires: 0\r\n'
      source.flush
    end

    #
    # Parses the 1st line of the incoming source request
    # @return array [6]: [ verb, url, scheme, host, port, path, req ]
    #
    def parse_req(req)
      verb = req[/^\w+/]
      url = req[/^\w+\s+(\S+)/, 1]
      v = req[/HTTP\/(1\.\d)\s*$/, 1]
      begin
        uri = URI::parse url
      rescue
        # last resort, try parsing "manually"
        scheme, host, path = url.match(/(https?):\/\/(.+)\/(.*)/).captures
        host, port = host.split ':'
        port = DEFAULT_PORT if not port && scheme == DEFAULT_SCHEME
        port = DEFAULT_SECURE_PORT if not port && scheme == DEFAULT_SECURE_SCHEME
        return [ verb, url, scheme, host, port, path, req ]
      end
      if verb == VERB_CONNECT
        # this is https request (to be included later)
        #host, port = url.split ':'
        #scheme = DEFAULT_SECURE_SCHEME
        #return [ VERB_CONNECT, url, scheme, host, port, nil, req ]
      end
      [ verb, url, uri.scheme, uri.host, uri.port, uri.path, req ]
    end

    #
    # Creates a socket to the target
    #
    def tcp_proxy(scheme, host, port)
      tcp_proxy = TCPSocket.new host, port
      if scheme == DEFAULT_SECURE_SCHEME
        # https socket placeholder
      end
      tcp_proxy
    end

    #
    # Prints out the cache statistics
    #
    def print_cash_stats
      cache_stats = @cache.stats
      @logger.info "(cache$) stats: #{cache_stats[0]}/#{cache_stats[1]} in #{cache_stats[2]}(#{cache_stats[3]}b)"
    end
  end

end


# Entry point:
if $0 == __FILE__

  port = ARGV[0]
  port = 8992 if not port
  cached = ARGV[1]
  cached = true if not cached
  verbose = ARGV[2]
  verbose = true if not verbose

  puts '====================================='
  puts ' | Arguments:'
  puts " |----- port=#{port}"
  puts " |----- cached=#{cached}"
  puts " |----- verbose=#{verbose}"
  puts '====================================='

  VERBOSE = (verbose == 'true') ? true : false
  cached = (cached == 'true') ? true : false
  proxy = Proxy::HTTP.new port, 70, cached
  proxy.listen

end