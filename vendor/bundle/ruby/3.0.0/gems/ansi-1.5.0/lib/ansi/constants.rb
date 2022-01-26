module ANSI

  require 'ansi/chart'

  # Converts {CHART} and {SPECIAL_CHART} entries into constants.
  # So for example, the CHART entry for :red becomes:
  #
  #   ANSI::Constants::RED  #=> "\e[31m"
  #
  # The ANSI Constants are include into ANSI::Code and can be included
  # any where will they would be of use.
  #
  module Constants

    CHART.each do |name, code|
      const_set(name.to_s.upcase, "\e[#{code}m")
    end

    SPECIAL_CHART.each do |name, code|
      const_set(name.to_s.upcase, code)
    end

  end

end
