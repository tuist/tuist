require "multi_test"

begin
  MultiTest.extend_with_best_assertion_library(self)
rescue NoMethodError => e
  if e.message =~ /extend_world/
    raise 'no assertion library detected'
  else
    raise e
  end
end
