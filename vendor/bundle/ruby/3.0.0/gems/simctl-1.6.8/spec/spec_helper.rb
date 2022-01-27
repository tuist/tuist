require 'cfpropertylist'
require 'coveralls'
require 'simplecov'
SimpleCov.start do
  add_filter 'spec'
end
Coveralls.wear!

$LOAD_PATH.push File.expand_path('../../lib', __FILE__)
require File.dirname(__FILE__) + '/../lib/simctl.rb'

SimCtl.default_timeout = if ENV['TRAVIS']
                           300
                         else
                           60
                         end

SimCtl.device_set_path = Dir.mktmpdir 'foo bar' if ENV['CUSTOM_DEVICE_SET_PATH']

RSpec.configure do |config|
  config.tty = true

  config.expect_with :rspec do |c|
    c.syntax = :expect
  end

  config.mock_with :rspec do |c|
    c.syntax = :expect
  end

  def with_rescue(&block)
    block.class
  rescue
  end

  def plist(path)
    plist = CFPropertyList::List.new(file: path)
    CFPropertyList.native_types(plist.value)
  end
end
