module Minitest
  # Filters backtraces of exceptions that may arise when running tests.
  class ExtensibleBacktraceFilter
    # Returns the default filter.
    #
    # The default filter will filter out all Minitest and minitest-reporters
    # lines.
    #
    # @return [Minitest::ExtensibleBacktraceFilter]
    def self.default_filter
      unless defined? @default_filter
        filter = self.new
        filter.add_filter(/lib\/minitest/)
        @default_filter = filter
      end

      @default_filter
    end

    # Creates a new backtrace filter.
    def initialize
      @filters = []
    end

    # Adds a filter.
    #
    # @param [Regex] regex the filter
    def add_filter(regex)
      @filters << regex
    end

    # Determines if the string would be filtered.
    #
    # @param [String] str
    # @return [Boolean]
    def filters?(str)
      @filters.any? { |filter| str =~ filter }
    end

    # Filters a backtrace.
    #
    # This will add new lines to the new backtrace until a filtered line is
    # encountered. If there were lines added to the new backtrace, it returns
    # those lines. However, if the first line in the backtrace was filtered,
    # resulting in an empty backtrace, it returns all lines that would have
    # been unfiltered. If that in turn does not contain any lines, it returns
    # the original backtrace.
    #
    # @param [Array] backtrace the backtrace to filter
    # @return [Array] the filtered backtrace
    # @note This logic is based off of Minitest's #filter_backtrace.
    def filter(backtrace)
      result = []
      return result unless backtrace

      backtrace.each do |line|
        break if filters?(line)
        result << line
      end

      result = backtrace.reject { |line| filters?(line) } if result.empty?
      result = backtrace.dup if result.empty?

      result
    end
  end
end
