spec = Gem::Specification.new do |s| 
  s.name = "scgi"
  s.version = "0.7.0"
  s.author = "Jeremy Evans"
  s.email = "code@jeremyevans.net"
  s.platform = Gem::Platform::RUBY
  s.summary = "Simple support for using SCGI in ruby apps, such as Rails"
  s.files = %w'COPYING README lib/scgi.rb lib/RailsSCGIProcessor.rb'
  s.require_paths = ["lib"]
  s.executables = %w'scgi_ctrl'
  s.has_rdoc = true
  s.rdoc_options = %w'--inline-source --line-numbers'
end
