#!/usr/local/bin/ruby

require 'stringio'
require 'socket'
require 'cgi'
require 'monitor'
require 'singleton'

module SCGI
  # A factory that makes Log objects, making sure that one Log is associated
  # with each log file.
  class LogFactory < Monitor
    include Singleton
    
    def initialize
      super()
      @@logs = {}
    end
      
    def create(file)
      synchronize{@@logs[file] ||= Log.new(file)}
    end
  end
    
  # A simple Log class that has an info and error method for output
  # messages to a log file.  The main thing this logger does is 
  # include the process ID in the logs so that you can see which child
  # is creating each message.
  class Log < Monitor
    def initialize(file)
      super()
      @out = open(file, "a+")
      @out.sync = true
      @pid = Process.pid
      @info = "[INF][#{@pid}] "
      @error = "[ERR][#{@pid}] "
    end
    
    def info(msg)
      synchronize{@out.print("#{@info}#{msg}\n")}
    end
    
    # If an exception is given then it will print the exception and a stack trace.
    def error(msg, exc=nil)
      return synchronize{@out.print("#{@error}#{msg}\n")} unless exc
      synchronize{@out.print("#{@error}#{msg}: #{exc}\n#{exc.backtrace.join("\n")}\n")}
    end
  end

  # Modifies CGI so that we can use it.  Main thing it does is expose
  # the stdinput and stdoutput so SCGI::Processor can connect them to
  # the right sources.  It also exposes the env_table so that SCGI::Processor
  # and hook the SCGI parameters into the environment table.
  class CGIFixed < ::CGI
    public :env_table
    attr_reader :args, :env_table

    def initialize(params, data, out, *args)
      @env_table = params
      @args = *args
      @input = StringIO.new(data)
      @out = out
      super(*args)
    end
    
    def stdinput
      @input
    end
    
    def stdoutput
      @out
    end
  end

  # This is the complete guts of the SCGI system.  It is designed so that
  # people can take it and implement it for their own systems, not just 
  # Ruby on Rails.  This implementation is not complete since you must
  # create your own that implements the process_request method.
  #
  # The SCGI protocol only works with TCP/IP sockets and not domain sockets.
  # It might be useful for shared hosting people to have domain sockets, but
  # they aren't supported in Apache, and in lighttpd they're unreliable.
  # Also, domain sockets don't work so well on Windows.
  class Processor < Monitor
    def initialize(settings = {})
      @total_conns = 0
      @shutdown = false
      @dead = false
      @threads = Queue.new
      @log = LogFactory.instance.create(settings[:logfile] || 'log/scgi.log')
      @maxconns = settings[:maxconns] || 2**30-1
      super()
      setup_signals
    end
        
    # Starts the SCGI::Processor having it listen on the given socket. This
    # function does not return until a shutdown.
    def listen(socket)
      @socket = socket
      
      # we also need a small collector thread that does nothing
      # but pull threads off the thread queue and joins them
      @collector = Thread.new do
        while t = @threads.shift
          collect_thread(t)
          @total_conns += 1
        end
      end
        
      thread = Thread.new do
        loop do
          handle_client(@socket.accept)
          break if @shutdown and @threads.length <= 0
        end
      end
        
      # and then collect the listener thread which blocks until it exits
      collect_thread(thread)
      
      @socket.close unless @socket.closed?
      @dead = true
      @log.info("Exited accept loop. Shutdown complete.")
    end
    
    def collect_thread(thread)
      begin
        thread.join
      rescue Interrupt
        @log.info("Shutting down from SIGINT.")
      rescue IOError
        @log.error("received IOError #$!.  Web server may possibly be configured wrong.")
      rescue Object
        @log.error("Collecting thread", $!)
      end
    end
    
    # Internal function that handles a new client connection.
    # It spawns a thread to handle the client and registers it in the 
    # @threads queue.  A collector thread is responsible for joining these
    # and clearing them out.  This design is needed because Ruby's GC
    # doesn't seem to deal with threads as well as others believe.
    #
    # Depending on how your system works, you may need to synchronize 
    # inside your process_request implementation.  scgi_rails.rb
    # does this so that Rails will run as if it were single threaded.
    #
    # It also handles calculating the current and total connections,
    # and deals with the graceful shutdown.  The important part 
    # of graceful shutdown is that new requests get redirected to
    # the /busy.html file.
    #
    def handle_client(socket)
      # ruby's GC seems to do weird things if we don't assign the thread to a local variable
      @threads << Thread.new do
        begin
          len = ""
          # we only read 10 bytes of the length.  any request longer than this is invalid
          while len.length <= 10
            c = socket.read(1)
            break if c == ':' # found the terminal, len now has a length in it so read the payload
            len << c
          end
          
          # we should now either have a payload length to get
          payload = socket.read(len.to_i)
          if socket.read(1) == ','
            read_header(socket, payload)
          else
            @log.error("Malformed request, does not end with ','")
          end
        rescue Object
          @log.error("Handling client", $!)
        ensure
          # no matter what we have to put this thread on the bad list
          socket.close if not socket.closed?
        end
      end
    end
    
    # Does three jobs:  reads and parses the SCGI netstring header,
    # reads any content off the socket, and then either calls process_request
    # or immediately returns a redirect to /busy.html for some connections.
    #
    # The browser/connection that will be redirected to /busy.html if 
    # either SCGI::Processor is in the middle of a shutdown, or if the
    # number of connections is over the @maxconns.  This redirect is
    # immediate and doesn't run inside the interpreter, so it will happen with
    # much less processing and help keep your system responsive.
    def read_header(socket, payload)
      return if socket.closed?
      request = Hash[*(payload.split("\0"))]
      if request["CONTENT_LENGTH"]
        length = request["CONTENT_LENGTH"].to_i
        body = length > 0 ? socket.read(length) : ''
        
        if @shutdown or @threads.length > @maxconns
          socket.write("Location: /busy.html\r\nCache-control: no-cache, must-revalidate\r\nExpires: Mon, 26 Jul 1997 05:00:00 GMT\r\nStatus: 307 Temporary Redirect\r\n\r\n")
        else
          process_request(request, body, socket)
        end
      end
    end
    
    # You must implement this yourself.  The request is a Hash
    # of the CGI parameters from the webserver.  The body is the
    # raw CGI body.  The socket is where you write your results
    # (properly HTTP formatted) back to the webserver.
    def process_request(request, body, socket)
      raise "You must implement process_request"
    end
    
    # Sets up the POSIX signals:
    #
    # * TERM -- Forced shutdown.
    # * INT -- Graceful shutdown.
    # * HUP -- Graceful shutdown.
    # * USR2 -- Dumps status info to the logs.  Super ugly.
    def setup_signals
      trap("TERM") { @log.info("SIGTERM, forced shutdown."); shutdown(force=true) }
      trap("INT") { @log.info("SIGINT, graceful shutdown started."); shutdown }
      trap("HUP") { @log.info("SIGHUP, graceful shutdown started."); shutdown }
      trap("USR2") { @log.info(status_info) }
    end
        
    # Returns a Hash with status information.  This is used
    # when dumping data to the logs
    def status_info
      { 
      :time => Time.now,  :pid => Process.pid, :started => @started,
      :max_conns => @maxconns, :conns => @threads.length, :systimes => Process.times,
      :shutdown => @shutdown, :dead => @dead, :total_conns => @total_conns
      }.inspect
    end
        
    # When called it will set the @shutdown flag indicating to the 
    # SCGI::Processor.listen function that all new connections should
    # be set to /busy.html, and all current connections should be 
    # "valved" off.  Once all the current connections are gone the
    # SCGI::Processor.listen function will exit.
    #
    # Use the force=true parameter to force an immediate shutdown.
    # This is done by closing the listening socket, so it's rather
    # violent.
    def shutdown(force = false)
      synchronize do
        @shutdown = true
        
        if @threads.length == 0 
          @log.info("Immediate shutdown since nobody is connected.")
          @socket.close
        elsif force
          @log.info("Forcing shutdown.  You may see exceptions.")
          @socket.close
        else
          @log.info("Shutdown requested.  Beginning graceful shutdown with #{@threads.length} connected.")
        end
      end
    end        
  end
end
