# frozen_string_literal: true

# See https://github.com/cucumber/cucumber/issues/693
if defined? Encoding
  Encoding.default_external = 'utf-8'
  Encoding.default_internal = 'utf-8'
end
