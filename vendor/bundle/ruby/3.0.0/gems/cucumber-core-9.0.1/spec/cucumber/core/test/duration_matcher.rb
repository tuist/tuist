# -*- encoding: utf-8 -*-
# frozen_string_literal: true
require 'cucumber/core/test/result'
require 'rspec/expectations'

module Cucumber::Core::Test
  RSpec::Matchers.define :be_duration do |expected|
    match do |actual|
      actual.tap { |duration| @nanoseconds = duration.nanoseconds }
      @nanoseconds == expected
    end
  end

  RSpec::Matchers.define :an_unknown_duration do
    match do |actual|
      actual.tap { raise "#tap block was executed, not an UnknownDuration" }
      expect(actual).to respond_to(:nanoseconds)
    end
  end
end
