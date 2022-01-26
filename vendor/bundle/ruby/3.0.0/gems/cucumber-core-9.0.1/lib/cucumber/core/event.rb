module Cucumber
  module Core
    class Event

      # Macro to generate new sub-classes of {Event} with
      # attribute readers.
      def self.new(*attributes)
        # Use normal constructor for subclasses of Event
        return super if self.ancestors.index(Event) > 0

        Class.new(Event) do
          attr_reader(*attributes)

          define_method(:initialize) do |*args|
            attributes.zip(args) do |name, value|
              instance_variable_set "@#{name}".to_sym, value
            end
          end

          define_method(:attributes) do
            attributes.map { |attribute| self.send(attribute) }
          end

          define_method(:to_h) do
            attributes.reduce({}) { |result, attribute|
              value = self.send(attribute)
              result[attribute] = value
              result
            }
          end

          define_method(:event_id) do
            self.class.event_id
          end
        end
      end


      class << self

        # @return [Symbol] the underscored name of the class to be used
        #                  as the key in an event registry.
        def event_id
          underscore(self.name.split("::").last).to_sym
        end

        private

        def underscore(string)
          string.to_s.gsub(/::/, '/').
          gsub(/([A-Z]+)([A-Z][a-z])/, '\1_\2').
          gsub(/([a-z\d])([A-Z])/, '\1_\2').
          tr("-", "_").
          downcase
        end

      end

    end
  end
end
