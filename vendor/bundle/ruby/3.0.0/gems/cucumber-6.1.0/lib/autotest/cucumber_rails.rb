# frozen_string_literal: true

require 'autotest/rails'
require 'autotest/cucumber_mixin'

class Autotest::CucumberRails < Autotest::Rails
  include CucumberMixin
end
