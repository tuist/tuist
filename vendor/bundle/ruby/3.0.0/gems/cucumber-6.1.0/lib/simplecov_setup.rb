# frozen_string_literal: true

if ENV['SIMPLECOV']
  begin
    # Suppress warnings in order not to pollute stdout which tests expectations rely on
    $VERBOSE = nil if defined?(JRUBY_VERSION)

    require 'simplecov'

    SimpleCov.root(File.expand_path(File.dirname(__FILE__) + '/..'))
    SimpleCov.start do
      add_filter 'iso-8859-1_steps.rb'
      add_filter '.-ruby-core/'
      add_filter '/spec/'
      add_filter '/features/'
    end
  rescue LoadError
    warn('Unable to load simplecov')
  end
end
