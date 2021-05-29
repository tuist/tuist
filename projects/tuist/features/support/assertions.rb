# frozen_string_literal: true

require "minitest/spec"
require "minitest/assertions"

class MinitestWorld
  include Minitest::Assertions
  attr_accessor :assertions

  def initialize
    self.assertions = 0
  end
end

World do
  MinitestWorld.new
end
