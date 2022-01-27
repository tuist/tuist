require 'rake'
require 'rake/testtask'
require 'rake/clean'
require 'rbconfig'
require 'rspec/core/rake_task'

CLEAN.include("**/*.rbc", "**/*.rbx", "**/*.gem", "**/*.lock")

desc "Run the example program"
task :example do
  if File::ALT_SEPARATOR
    sh 'ruby -Ilib/windows examples/uname_test.rb'
  else
    sh 'ruby -Ilib/unix examples/uname_test.rb'
  end
end

namespace :gem do
  desc "Create the sys-uname gem"
  task :create => [:clean] do
    require 'rubygems/package'
    spec = eval(IO.read('sys-uname.gemspec'))
    spec.signing_key = File.join(Dir.home, '.ssh', 'gem-private_key.pem')
    Gem::Package.build(spec)
  end

  desc "Install the sys-uname gem"
  task :install => [:create] do
    file = Dir["*.gem"].first
    sh "gem install #{file}"
  end
end

desc "Run the test suite"
RSpec::Core::RakeTask.new(:spec)

task :default => :spec
