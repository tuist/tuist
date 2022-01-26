require 'test_helper'
require 'ansi/code'

testcase ANSI::Code do

  method :red do
    test do
      str = ANSI::Code.red
      out = "\e[31m"
      out.assert == str
    end

    test "with block notation" do
      str = ANSI::Code.red { "Hello" }
      out = "\e[31mHello\e[0m"
      out.assert == str
    end
  end

  method :blue do
    test do
      str = ANSI::Code.blue
      out = "\e[34m"
      out.assert == str
    end

    test "with block notation" do
      str = ANSI::Code.blue { "World" }
      out = "\e[34mWorld\e[0m"
      out.assert == str
    end
  end

  method :hex do
    test do
      str = ANSI::Code.hex("#000000")
      out = "0"
      out.assert == str
    end
  end

end

