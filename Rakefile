require 'rake'
require 'rake/clean'
begin
  require 'hanna/rdoctask'
rescue LoadError
  require 'rake/rdoctask'
end

CLEAN.include ["rdoc"]

Rake::RDocTask.new do |rdoc|
  rdoc.rdoc_dir = "rdoc"
  rdoc.options += ["--quiet", "--line-numbers", "--inline-source"]
  rdoc.main = "README"
  rdoc.title = "ruby-scgi"
  rdoc.rdoc_files.add ["README", "LICENSE", "lib/**/*.rb"]
end

desc "Update docs and upload to rubyforge.org"
task :doc_rforge => [:rdoc]
task :doc_rforge do
  sh %{chmod -R g+w rdoc/*}
  sh %{scp -rp rdoc/* rubyforge.org:/var/www/gforge-projects/scgi}
end

desc "Package ruby-scgi"
task :package do
  sh %{gem build scgi.gemspec}
end
