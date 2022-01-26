# encoding: UTF-8
# frozen_string_literal: true

module TZInfo
  # Object#untaint is deprecated in Ruby >= 2.7 and will be removed in 3.2.
  # UntaintExt adds a refinement to make Object#untaint a no-op and avoid the
  # warning.
  #
  # @private
  module UntaintExt # :nodoc:
    refine Object do
      def untaint
        self
      end
    end
  end
  private_constant :UntaintExt
end
