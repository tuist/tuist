# encoding: UTF-8
# frozen_string_literal: true

# The top level module for TZInfo.
module TZInfo
end

# Object#untaint is a deprecated no-op in Ruby >= 2.7 and will be removed in
# 3.2. Add a refinement to either silence the warning, or supply the method if
# needed.
if !Object.new.respond_to?(:untaint) || RUBY_VERSION =~ /\A(\d+)\.(\d+)(?:\.|\z)/ && ($1 == '2' && $2.to_i >= 7 || $1.to_i >= 3)
  require_relative 'tzinfo/untaint_ext'
end

require_relative 'tzinfo/version'

require_relative 'tzinfo/string_deduper'

require_relative 'tzinfo/timestamp'

require_relative 'tzinfo/with_offset'
require_relative 'tzinfo/datetime_with_offset'
require_relative 'tzinfo/time_with_offset'
require_relative 'tzinfo/timestamp_with_offset'

require_relative 'tzinfo/timezone_offset'
require_relative 'tzinfo/timezone_transition'
require_relative 'tzinfo/transition_rule'
require_relative 'tzinfo/annual_rules'

require_relative 'tzinfo/data_sources'
require_relative 'tzinfo/data_sources/timezone_info'
require_relative 'tzinfo/data_sources/data_timezone_info'
require_relative 'tzinfo/data_sources/linked_timezone_info'
require_relative 'tzinfo/data_sources/constant_offset_data_timezone_info'
require_relative 'tzinfo/data_sources/transitions_data_timezone_info'

require_relative 'tzinfo/data_sources/country_info'

require_relative 'tzinfo/data_sources/posix_time_zone_parser'
require_relative 'tzinfo/data_sources/zoneinfo_reader'

require_relative 'tzinfo/data_source'
require_relative 'tzinfo/data_sources/ruby_data_source'
require_relative 'tzinfo/data_sources/zoneinfo_data_source'

require_relative 'tzinfo/timezone_period'
require_relative 'tzinfo/offset_timezone_period'
require_relative 'tzinfo/transitions_timezone_period'
require_relative 'tzinfo/timezone'
require_relative 'tzinfo/info_timezone'
require_relative 'tzinfo/data_timezone'
require_relative 'tzinfo/linked_timezone'
require_relative 'tzinfo/timezone_proxy'

require_relative 'tzinfo/country'
require_relative 'tzinfo/country_timezone'

require_relative 'tzinfo/format2'
require_relative 'tzinfo/format2/country_definer'
require_relative 'tzinfo/format2/country_index_definer'
require_relative 'tzinfo/format2/country_index_definition'
require_relative 'tzinfo/format2/timezone_definer'
require_relative 'tzinfo/format2/timezone_definition'
require_relative 'tzinfo/format2/timezone_index_definer'
require_relative 'tzinfo/format2/timezone_index_definition'

require_relative 'tzinfo/format1'
require_relative 'tzinfo/format1/country_definer'
require_relative 'tzinfo/format1/country_index_definition'
require_relative 'tzinfo/format1/timezone_definer'
require_relative 'tzinfo/format1/timezone_definition'
require_relative 'tzinfo/format1/timezone_index_definition'
