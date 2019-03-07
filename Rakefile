# frozen_string_literal: true

require 'rubygems'
require 'cucumber'
require 'cucumber/rake/task'
require 'mkmf'

Cucumber::Rake::Task.new(:features) do |t|
  t.cucumber_opts = "--format pretty"
end

desc("Formats the code style")
task :style_correct do
  system("swiftformat", ".")
  system("swiftlint", "autocorrect")
end

desc("Lints the Ruby code style")
task :style_ruby do
  system("bundle", "exec", "rubocop")
end

desc("Corrects the issues with the Ruby style")
task :style_ruby_correct do
  system("bundle", "exec", "rubocop", "-a")
end

def system(*args)
  Kernel.system(*args) || abort
end