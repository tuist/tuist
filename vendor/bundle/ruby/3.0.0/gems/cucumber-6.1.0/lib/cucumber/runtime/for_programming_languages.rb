# frozen_string_literal: true

require 'forwardable'
require 'cucumber/core/test/doc_string'

module Cucumber
  class Runtime
    # This is what a programming language will consider to be a runtime.
    #
    # It's a thin class that directs the handul of methods needed by the
    # programming languages to the right place.
    class ForProgrammingLanguages
      extend Forwardable

      attr_reader :support_code

      def initialize(support_code, user_interface)
        @support_code = support_code
        @user_interface = user_interface
      end

      def_delegators :@user_interface,
                     :embed,
                     :attach,
                     :ask,
                     :puts,
                     :features_paths,
                     :step_match

      def_delegators :@support_code,
                     :invoke_dynamic_steps,
                     :invoke_dynamic_step
    end
  end
end
