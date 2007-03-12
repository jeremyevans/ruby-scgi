#!/usr/local/bin/ruby
require 'scgi'

class RailsProcessor < SCGI::Processor 
  DEFAULT_SCGI_RAILS_SETTINGS = {:environment=>'production', :bind=>'127.0.0.1', 
    :port=>9999, :logfile=>'log/scgi.log', :maxconns=>2**30-1}
    
  def initialize(settings)
    settings = DEFAULT_SCGI_RAILS_SETTINGS.merge(settings)
    ENV["RAILS_ENV"] = settings[:environment]
    require "config/environment"
    ActiveRecord::Base.threaded_connections = false
    require 'dispatcher'
    super(settings)
    @guard = Mutex.new
  end
  
  def process_request(request, body, socket)
    return if socket.closed?
    cgi = SCGI::CGIFixed.new(request, body, socket)
    begin
      @guard.synchronize{Dispatcher.dispatch(cgi, ActionController::CgiRequest::DEFAULT_SESSION_OPTIONS, cgi.stdoutput)}
    rescue IOError
      @log.error("received IOError #$! when handling client.  Your web server doesn't like me.")
    rescue Object => rails_error
      @log.error("calling Dispatcher.dispatch", rails_error)
    end
  end
end
