# frozen_string_literal: true
require 'cucumber/core/test/timer'
require 'cucumber/core/test/duration_matcher'

module Cucumber
  module Core
    module Test
      describe Timer do
        before do
          allow(Timer::MonotonicTime).to receive(:time_in_nanoseconds)
                                            .and_return(525702744080000, 525702744080001)
        end

        it "returns a Result::Duration object" do
          timer = Timer.new.start
          expect( timer.duration ).to be_duration 1
        end

        it "would be slow to test" do
          # so we won't
        end
      end
    end
  end
end
