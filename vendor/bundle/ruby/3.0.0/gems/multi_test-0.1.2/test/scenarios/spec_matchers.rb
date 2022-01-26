require "multi_test"

# Now we create the world
MultiTest.extend_with_best_assertion_library(self)

# Now we execute a scenario and assert something
1.should == 1
