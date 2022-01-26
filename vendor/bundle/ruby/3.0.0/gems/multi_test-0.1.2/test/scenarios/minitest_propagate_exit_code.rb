# Imagine this is your rails app
require 'minitest/autorun'

# Now cucumber loads and exits successfully
require "multi_test"
MultiTest.disable_autorun
exit 0

# Our Minitest hook should propagate that healthy status code
