spec = Gem::Specification.new do |s| 
  s.name = "scgi"
  s.version = "0.9.0"
  s.author = "Jeremy Evans"
  s.email = "code@jeremyevans.net"
  s.platform = Gem::Platform::RUBY
  s.summary = "Simple support for using SCGI in ruby apps, such as Rails"
  s.files = %w'LICENSE README lib/scgi.rb'
  s.extra_rdoc_files = ['README']
  s.require_paths = ["lib"]
  s.has_rdoc = true
  s.rdoc_options = %w'--inline-source --line-numbers'
  s.rubyforge_project = 'scgi'
end
