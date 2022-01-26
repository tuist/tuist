module Protobuf
  module Rpc
    module ServiceFilters

      def self.included(other)
        other.class_eval do
          extend Protobuf::Rpc::ServiceFilters::ClassMethods
          include Protobuf::Rpc::ServiceFilters::InstanceMethods
        end
      end

      module ClassMethods

        [:after, :around, :before].each do |type|
          # Setter DSL method for given filter types.
          #
          define_method "#{type}_filter" do |*args|
            set_filters(type, *args)
          end
          alias_method "#{type}_action", "#{type}_filter"
        end

        # Filters hash keyed based on filter type (e.g. :before, :after, :around),
        # whose values are Sets.
        #
        def filters
          @filters ||= Hash.new { |h, k| h[k] = [] }
        end

        # Filters hash keyed based on filter type (e.g. :before, :after, :around),
        # whose values are Sets.
        #
        def rescue_filters
          @rescue_filters ||= {}
        end

        def rescue_from(*ex_klasses, &block)
          options = ex_klasses.last.is_a?(Hash) ? ex_klasses.pop : {}
          callable = options.delete(:with) { block }
          fail ArgumentError, 'Option :with missing from rescue_from options' if callable.nil?
          ex_klasses.each { |ex_klass| rescue_filters[ex_klass] = callable }
        end

        private

        def define_filter(type, filter, options = {})
          return if filter_defined?(type, filter)
          filters[type] << options.merge(:callable => filter)
          remember_filter(type, filter)
        end

        def defined_filters
          @defined_filters ||= Hash.new { |h, k| h[k] = Set.new }
        end

        # Check to see if the filter has been defined.
        #
        def filter_defined?(type, filter)
          defined_filters[type].include?(filter)
        end

        # Remember that we stored the filter.
        #
        def remember_filter(type, filter)
          defined_filters[type] << filter
        end

        # Takes a list of actually (or potentially) callable objects.
        # TODO: add support for if/unless
        # TODO: add support for only/except sub-filters
        #
        def set_filters(type, *args)
          options = args.last.is_a?(Hash) ? args.pop : {}
          args.each do |filter|
            define_filter(type, filter, options)
          end
        end

      end

      module InstanceMethods

        private

        # Get back to class filters.
        #
        def filters
          self.class.filters
        end

        # Predicate which uses the filter options to determine if the filter
        # should be called. Specifically checks the :if, :unless, :only, and :except
        # options for every filter. Each option check is expected to return false
        # if the filter should not be invoked, true if invocation should occur.
        #
        def invoke_filter?(rpc_method, filter)
          invoke_via_only?(rpc_method, filter) &&
            invoke_via_except?(rpc_method, filter) &&
            invoke_via_if?(rpc_method, filter) &&
            invoke_via_unless?(rpc_method, filter)
        end

        # If the target rpc endpoint method is listed under an :except option,
        # return false to indicate that the filter should not be invoked. Any
        # other target rpc endpoint methods not listed should be invoked.
        # This option is the opposite of :only.
        #
        # Value should be a symbol/string or an array of symbols/strings.
        #
        def invoke_via_except?(rpc_method, filter)
          except = [filter.fetch(:except) { [] }].flatten
          except.empty? || !except.include?(rpc_method)
        end

        # Invoke the given :if callable (if any) and return its return value.
        # Used by `invoke_filter?` which expects a true/false
        # return value to determine if we should invoke the target filter.
        #
        # Value can either be a symbol/string indicating an instance method to call
        # or an object that responds to `call`.
        #
        def invoke_via_if?(_rpc_method, filter)
          if_check = filter.fetch(:if, nil)
          return true if if_check.nil?
          call_or_send(if_check)
        end

        # If the target rpc endpoint method is listed in the :only option,
        # it should be invoked. Any target rpc endpoint methods not listed in this
        # option should not be invoked. This option is the opposite of :except.
        #
        # Value should be a symbol/string or an array of symbols/strings.
        #
        def invoke_via_only?(rpc_method, filter)
          only = [filter.fetch(:only) { [] }].flatten
          only.empty? || only.include?(rpc_method)
        end

        # Invoke the given :unless callable (if any) and return the opposite
        # of it's return value. Used by `invoke_filter?` which expects a true/false
        # return value to determine if we should invoke the target filter.
        #
        # Value can either be a symbol/string indicating an instance method to call
        # or an object that responds to `call`.
        #
        def invoke_via_unless?(_rpc_method, filter)
          unless_check = filter.fetch(:unless, nil)
          return true if unless_check.nil?
          !call_or_send(unless_check)
        end

        def rescue_filters
          self.class.rescue_filters
        end

        # Loop over the unwrapped filters and invoke them. An unwrapped filter
        # is either a before or after filter, not an around filter.
        #
        def run_unwrapped_filters(unwrapped_filters, rpc_method, stop_on_false_return = false)
          unwrapped_filters.each do |filter|
            if invoke_filter?(rpc_method, filter)
              return_value = call_or_send(filter[:callable])
              return false if stop_on_false_return && return_value == false
            end
          end

          true
        end

        # Reverse build a chain of around filters. To implement an around chain,
        # simply build a method that yields control when it expects the underlying
        # method to be invoked. If the endpoint should not be run (due to some
        # condition), simply do not yield.
        #
        # Around filters are invoked in the order they are defined, outer to inner,
        # with the inner-most method called being the actual rpc endpoint.
        #
        # Let's say you have a class defined with the following filters:
        #
        #   class MyService
        #     around_filter :filter1, :filter2, :filter3
        #
        #     def my_endpoint
        #       # do stuff
        #     end
        #   end
        #
        # When the my_endpoint method is invoked using Service#callable_rpc_method,
        # It is similar to this call chain:
        #
        #   filter1 do
        #     filter2 do
        #       filter3 do
        #         my_endpoint
        #       end
        #     end
        #   end
        #
        def run_around_filters(rpc_method)
          final = -> { __send__(rpc_method) }
          filters[:around].reverse.reduce(final) do |previous, filter|
            if invoke_filter?(rpc_method, filter)
              -> { call_or_send(filter[:callable], &previous) }
            else
              previous
            end
          end.call
        end

        # Entry method to call each filter type in the appropriate order. This should
        # be used instead of the other run methods directly.
        #
        def run_filters(rpc_method)
          run_rescue_filters do
            continue = run_unwrapped_filters(filters[:before], rpc_method, true)
            if continue
              run_around_filters(rpc_method)
              run_unwrapped_filters(filters[:after], rpc_method)
            end
          end
        end

        def run_rescue_filters
          if rescue_filters.keys.empty?
            yield
          else
            begin
              yield
            rescue *rescue_filters.keys => ex
              callable = rescue_filters.fetch(ex.class) do
                mapped_klass = rescue_filters.keys.find { |child_klass| ex.class < child_klass }
                rescue_filters[mapped_klass]
              end

              call_or_send(callable, ex)
            end
          end
        end

        # Call the object if it is callable, otherwise invoke the method using
        # __send__ assuming that we respond_to it. Return the call's return value.
        #
        def call_or_send(callable, *args, &block)
          return callable.call(self, *args, &block) if callable.respond_to?(:call)
          __send__(callable, *args, &block)
        end
      end
    end
  end
end
