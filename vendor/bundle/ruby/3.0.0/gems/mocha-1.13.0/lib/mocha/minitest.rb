require 'mocha/integration/mini_test'
require 'mocha/deprecation'

unless Mocha::Integration::MiniTest.activate
  Mocha::Deprecation.warning(
    "MiniTest must be loaded *before* `require 'mocha/minitest'`."
  )
end
