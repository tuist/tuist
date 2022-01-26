require 'bundler/setup'
require 'bundler/gem_tasks'

begin
  require 'rspec/core/rake_task'
  require 'rubocop/rake_task'

  RSpec::Core::RakeTask.new(:test)
  RuboCop::RakeTask.new(:rubocop)

  task default: %i[rubocop test]
rescue LoadError
  puts 'RSpec rake tasks not available. Please run "bundle install" to install missing dependencies.'
end
