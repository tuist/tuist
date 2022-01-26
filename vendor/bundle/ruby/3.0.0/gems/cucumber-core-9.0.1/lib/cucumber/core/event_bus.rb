require 'cucumber/core/events'

module Cucumber
  module Core

    # Event Bus
    #
    # Implements an in-process pub-sub event broadcaster allowing multiple observers
    # to subscribe to events that fire as your tests are executed.
    #
    class EventBus
      attr_reader :event_types

      # @param registry [Hash{Symbol => Class}] a hash of event types to use on the bus
      def initialize(registry = Events.registry)
        @event_types = registry.freeze
        @handlers = {}
        @event_queue = []
      end

      # Register for an event. The handler proc will be called back with each of the attributes
      # of the event.
      def on(event_id, handler_object = nil, &handler_proc)
        handler = handler_proc || handler_object
        validate_handler_and_event_id!(handler, event_id)
        event_class = event_types[event_id]
        handlers_for(event_class) << handler
        broadcast_queued_events_to handler, event_class
      end

      # Broadcast an event
      def broadcast(event)
        raise ArgumentError, "Event type #{event.class} is not registered. Try one of these:\n#{event_types.values.join("\n")}" unless is_registered_type?(event.class)
        handlers_for(event.class).each { |handler| handler.call(event) }
        @event_queue << event
      end

      def method_missing(event_id, *args)
        event_class = event_types.fetch(event_id) { super }
        broadcast event_class.new(*args)
      end

      private

      def broadcast_queued_events_to(handler, event_type)
        @event_queue.select { |event|
          event.instance_of?(event_type)
        }.each { |event|
          handler.call(event)
        }
      end

      def handlers_for(event_class)
        @handlers[event_class.to_s] ||= []
      end

      def is_registered_id?(event_id)
        event_types.keys.include?(event_id)
      end

      def is_registered_type?(event_type)
        event_types.values.include?(event_type)
      end

      def validate_handler_and_event_id!(handler, event_id)
        raise ArgumentError, "Please pass either an object or a handler block" unless handler
        raise ArgumentError, "Please use a symbol for the event_id" unless event_id.is_a?(Symbol)
        raise ArgumentError, "Event ID #{event_id} is not recognised. Try one of these:\n#{event_types.keys.join("\n")}" unless is_registered_id?(event_id)
      end
    end

  end
end
