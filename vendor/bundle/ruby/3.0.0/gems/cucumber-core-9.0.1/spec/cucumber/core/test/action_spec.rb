# frozen_string_literal: true
require 'cucumber/core/test/action'
require 'cucumber/core/test/duration_matcher'

module Cucumber
  module Core
    module Test

      describe Action do

        context "constructed without a block" do
          it "raises an error" do
            expect { Action.new }.to raise_error(ArgumentError)
          end
        end

        context "location" do

          context "with location passed to the constructor" do
            let(:location) { double }

            it "returns the location passed to the constructor" do
              action = Action.new(location) {}
              expect( action.location ).to be location
            end
          end

          context "without location passed to the constructor" do
            let(:block) { proc {} }

            it "returns the location of the block passed to the constructor" do
              action = Action.new(&block)
              expect( action.location ).to eq Test::Location.new(*block.source_location)
            end
          end

        end

        context "executing" do
          it "executes the block passed to the constructor" do
            executed = false
            action = Action.new { executed = true }
            action.execute
            expect( executed ).to be_truthy
          end

          it "returns a passed result if the block doesn't fail" do
            action = Action.new {}
            expect( action.execute ).to be_passed
          end

          it "returns a failed result when the block raises an error" do
            exception = StandardError.new
            action = Action.new { raise exception }
            result = action.execute
            expect( result ).to be_failed
            expect( result.exception ).to eq exception
          end

          it "yields the args passed to #execute to the block" do
            args = [double, double]
            args_spy = nil
            action = Action.new { |arg1, arg2| args_spy = [arg1, arg2] }
            action.execute(*args)
            expect(args_spy).to eq args
          end

          it "returns a pending result if a Result::Pending error is raised" do
            exception = Result::Pending.new("TODO")
            action = Action.new { raise exception }
            result = action.execute
            expect( result ).to be_pending
            expect( result.message ).to eq "TODO"
          end

          it "returns a skipped result if a Result::Skipped error is raised" do
            exception = Result::Skipped.new("Not working right now")
            action = Action.new { raise exception }
            result = action.execute
            expect( result ).to be_skipped
            expect( result.message ).to eq "Not working right now"
          end

          it "returns an undefined result if a Result::Undefined error is raised" do
            exception = Result::Undefined.new("new step")
            action = Action.new { raise exception }
            result = action.execute
            expect( result ).to be_undefined
            expect( result.message ).to eq "new step"
          end

          context "recording the duration" do
            before do
              allow( Timer::MonotonicTime ).to receive(:time_in_nanoseconds).and_return(525702744080000, 525702744080001)
            end

            it "records the nanoseconds duration of the execution on the result" do
              action = Action.new { }
              duration = action.execute.duration
              expect( duration ).to be_duration 1
            end

            it "records the duration of a failed execution" do
              action = Action.new { raise StandardError }
              duration = action.execute.duration
              expect( duration ).to be_duration 1
            end
          end

        end

        context "skipping" do
          it "does not execute the block" do
            executed = false
            action = Action.new { executed = true }
            action.skip
            expect( executed ).to be_falsey
          end

          it "returns a skipped result" do
            action = Action.new {}
            expect( action.skip ).to be_skipped
          end
        end
      end

      describe UndefinedAction do
        let(:location) { double }
        let(:action) { UndefinedAction.new(location) }
        let(:test_step) { double }

        context "location" do
          it "returns the location passed to the constructor" do
            expect( action.location ).to be location
          end
        end

        context "executing" do
          it "returns an undefined result" do
            expect( action.execute ).to be_undefined
          end
        end

        context "skipping" do
          it "returns an undefined result" do
            expect( action.skip ).to be_undefined
          end
        end
      end

    end
  end
end
