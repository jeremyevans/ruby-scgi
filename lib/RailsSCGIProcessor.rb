#!/usr/local/bin/ruby
require 'scgi'

# This SCGI::Processor subclass hooks the SCGI request into Ruby on Rails.
class RailsSCGIProcessor < SCGI::Processor 
  # Initialzes Rails with the appropriate environment and settings
  def initialize(settings)
    ENV["RAILS_ENV"] = settings[:environment] || 'production'
    require "config/environment"
    ActiveRecord::Base.threaded_connections = false
    require 'dispatcher'
    super(settings)
    @guard = Mutex.new
  end
  
  # Submits requests to Rails in a single threaded fashion
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
