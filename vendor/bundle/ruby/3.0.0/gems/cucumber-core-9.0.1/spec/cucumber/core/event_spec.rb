require 'cucumber/core/event'

module Cucumber
  module Core
    describe Event do

      describe ".new" do
        it "generates new types of events" do
          my_event_type = Event.new
          my_event = my_event_type.new
          expect(my_event).to be_kind_of(Core::Event)
        end

        it "generates events with attributes" do
          my_event_type = Event.new(:foo, :bar)
          my_event = my_event_type.new(1, 2)
          expect(my_event.attributes).to eq [1, 2]
          expect(my_event.foo).to eq 1
          expect(my_event.bar).to eq 2
        end
      end

      describe "a generated event" do
        class MyEventType < Event.new(:foo, :bar)
        end

        it "can be converted to a hash" do
          my_event = MyEventType.new(1, 2)
          expect(my_event.to_h).to eq foo: 1, bar: 2
        end

        it "has an event_id" do
          expect(MyEventType.event_id).to eq :my_event_type
          expect(MyEventType.new(1, 2).event_id).to eq :my_event_type
        end
      end
    end

  end
end
