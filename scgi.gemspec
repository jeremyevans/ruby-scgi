spec = Gem::Specification.new do |s| 
  s.name = "scgi"
  s.version = "0.5.0"
  s.author = "Jeremy Evans"
  s.email = "code@jeremyevans.net"
  s.platform = Gem::Platform::RUBY
  s.summary = "Simple support for using SCGI in ruby apps, such as Rails"
  s.files = %w'COPYING lib/scgi.rb lib/scgi_rails.rb'
  s.require_paths = ["lib"]
  s.executables = %w'scgi_ctrl scgi_rails_service'
  s.has_rdoc = true
end

