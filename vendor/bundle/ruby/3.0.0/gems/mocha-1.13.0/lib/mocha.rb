require 'mocha/version'
require 'mocha/ruby_version'
require 'mocha/deprecation'

if Mocha::PRE_RUBY_V19
  Mocha::Deprecation.warning(
    'Versions of Ruby earlier than v1.9 will not be supported in future versions of Mocha.'
  )
end
