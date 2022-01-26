module Protobuf
  class Lifecycle
    class << self
      def register(event_name)
        fail "Lifecycle register must have a block" unless block_given?
        event_name = normalized_event_name(event_name)

        ::ActiveSupport::Notifications.subscribe(event_name) do |_name, _start, _finish, _id, args|
          yield(*args)
        end
      end
      alias :on register

      def trigger(event_name, *args)
        event_name = normalized_event_name(event_name)

        ::ActiveSupport::Notifications.instrument(event_name, args)
      end

      replacement = ::ActiveSupport::Notifications

      ::Protobuf.deprecator.deprecate_methods(
        self,
        :register => "#{replacement}.#{replacement.method(:subscribe).name}".to_sym,
        :trigger => "#{replacement}.#{replacement.method(:instrument).name}".to_sym,
      )

      def normalized_event_name(event_name)
        event_name.to_s.downcase
      end
    end
  end
end
