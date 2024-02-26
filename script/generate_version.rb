#!/usr/bin/env ruby
# frozen_string_literal: true

current_time = Time.now
year = current_time.year
month = current_time.month.to_s.rjust(2, '0') # Add leading zero if necessary
day = current_time.day.to_s.rjust(2, '0') # Add leading zero if necessary

MAJOR = "1"

version = "#{MAJOR}.#{year % 100}.#{month}.#{day}"

puts version
