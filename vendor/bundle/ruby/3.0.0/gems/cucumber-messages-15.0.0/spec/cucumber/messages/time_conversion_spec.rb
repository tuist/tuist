require 'cucumber/messages'

module Cucumber
  module Messages
    describe TimeConversion do
      include TimeConversion

      it 'converts to and from milliseconds since epoch' do
        time = Time.now
        timestamp = time_to_timestamp(time)
        time_again = timestamp_to_time(timestamp)

        expect(time).to be_within(0.000001).of(time_again)
      end

      it 'converts to and from seconds duration' do
        duration_in_seconds = 1234
        duration = seconds_to_duration(duration_in_seconds)
        duration_in_seconds_again = duration_to_seconds(duration)

        expect(duration_in_seconds_again).to eq(duration_in_seconds)
      end

      it 'converts to and from seconds duration (with decimal places)' do
        duration_in_seconds = 3.000161
        duration = seconds_to_duration(duration_in_seconds)
        duration_in_seconds_again = duration_to_seconds(duration)

        expect(duration_in_seconds_again).to be_within(0.000000001).of(duration_in_seconds)
      end
    end
  end
end
