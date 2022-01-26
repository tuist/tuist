# frozen_string_literal: true

module Cucumber
  module Formatter
    # Forwards any messages sent to this object to all recipients
    # that respond to that message.
    class Fanout < BasicObject
      attr_reader :recipients
      private :recipients

      def initialize(recipients)
        @recipients = recipients
      end

      def method_missing(message, *args)
        super unless recipients

        recipients.each do |recipient|
          recipient.send(message, *args) if recipient.respond_to?(message)
        end
      end

      def respond_to_missing?(name, include_private = false)
        recipients.any? { |recipient| recipient.respond_to?(name, include_private) }
      end
    end
  end
end
