require 'mocha/integration'
require 'mocha/deprecation'

Mocha::Deprecation.warning(
  "Require 'mocha/test_unit', 'mocha/minitest' or 'mocha/api' instead of 'mocha/setup'."
)

module Mocha
  def self.activate
    Integration.activate
  end
end

Mocha.activate
