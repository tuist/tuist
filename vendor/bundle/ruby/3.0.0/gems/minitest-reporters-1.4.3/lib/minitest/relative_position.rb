module Minitest
  module RelativePosition
    TEST_PADDING = 2
    TEST_SIZE = 63
    MARK_SIZE = 5
    INFO_PADDING = 8

    private

    def print_with_info_padding(line)
      puts pad(line, INFO_PADDING)
    end

    def pad(str, size = INFO_PADDING)
      ' ' * size + str
    end

    def pad_mark(str)
      "%#{MARK_SIZE}s" % str
    end

    def pad_test(str)
      pad("%-#{TEST_SIZE}s" % str, TEST_PADDING)
    end
  end
end
