require 'mocha/integration/test_unit'
require 'mocha/deprecation'

unless Mocha::Integration::TestUnit.activate
  Mocha::Deprecation.warning(
    "Test::Unit must be loaded *before* `require 'mocha/test_unit'`."
  )
end
