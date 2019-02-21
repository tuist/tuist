# frozen_string_literal: true

require 'rubygems'
require 'cucumber'
require 'cucumber/rake/task'
require 'mkmf'

Cucumber::Rake::Task.new(:features) do |t|
  t.cucumber_opts = "--format pretty"
end

desc("Formats the code")
task :swiftformat do
  abort_unless_swiftformat_installed
  system("swiftformat", ".") || abort
end

desc("Lints the Ruby code style")
task :style_ruby do
  system("bundle", "exec", "rubocop") || abort
end

desc("Corrects the issues with the Ruby style")
task :style_ruby_correct do
  system("bundle", "exec", "rubocop", "-a") || abort
end

def abort_unless_swiftformat_installed
  abort("swiftformat not installed. Run 'brew install swiftformat'") unless find_executable('swiftformat')
end
