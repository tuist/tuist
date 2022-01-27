module Cucumber
  module Messages
    module TimeConversion
      NANOSECONDS_PER_SECOND = 1000000000

      def time_to_timestamp(time)
        Timestamp.new(
          seconds: time.to_i,
          nanos: time.nsec
        )
      end

      def timestamp_to_time(timestamp)
        Time.at(timestamp.seconds + timestamp.nanos.to_f / NANOSECONDS_PER_SECOND)
      end

      def seconds_to_duration(seconds_float)
        seconds, second_modulus = seconds_float.divmod(1)
        nanos = second_modulus * NANOSECONDS_PER_SECOND
        Duration.new(seconds: seconds, nanos: nanos)
      end

      def duration_to_seconds(duration)
        seconds_part = duration.seconds
        nanos_part = duration.nanos.to_f / NANOSECONDS_PER_SECOND
        seconds_part + nanos_part
      end
    end
  end
end
