# frozen_string_literal: true

require 'autotest/cucumber_mixin'
require 'autotest/rspec'

class Autotest::CucumberRspec < Autotest::Rspec
  include CucumberMixin
end
