# encoding: utf-8
require 'rubygems'
require 'bundler'
Bundler::GemHelper.install_tasks

$:.unshift File.expand_path("../lib", __FILE__)

Dir['./rake/*.rb'].each do |f|
  require f
end

require "rspec/core/rake_task"
RSpec::Core::RakeTask.new(:spec)

require_relative 'spec/capture_warnings'
include CaptureWarnings
namespace :spec do
  task :warnings do
    report_warnings do
      Rake::Task['spec'].invoke
    end
  end
end

task default: ['spec:warnings']
