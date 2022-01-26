require 'cucumber/wire/plugin'

AfterConfiguration do |config|
  Cucumber::Wire::Plugin.new(config).install
end
