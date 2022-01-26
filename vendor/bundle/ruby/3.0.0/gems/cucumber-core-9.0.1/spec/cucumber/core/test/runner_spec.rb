# frozen_string_literal: true
require 'cucumber/core/test/runner'
require 'cucumber/core/test/case'
require 'cucumber/core/test/step'
require 'cucumber/core/test/duration_matcher'

module Cucumber::Core::Test
  describe Runner do

    let(:step_id)   { double }
    let(:test_id)   { double }
    let(:name)      { double }
    let(:location)  { double }
    let(:tags)      { double }
    let(:language)  { double }
    let(:test_case) { Case.new(test_id, name, test_steps, location, tags, language) }
    let(:text)      { double }
    let(:runner)    { Runner.new(event_bus) }
    let(:event_bus) { double.as_null_object }
    let(:passing)   { Step.new(step_id, text, location, location).with_action {} }
    let(:failing)   { Step.new(step_id, text, location, location).with_action { raise exception } }
    let(:pending)   { Step.new(step_id, text, location, location).with_action { raise Result::Pending.new("TODO") } }
    let(:skipping)  { Step.new(step_id, text, location, location).with_action { raise Result::Skipped.new } }
    let(:undefined) { Step.new(step_id, text, location, location) }
    let(:exception) { StandardError.new('test error') }

    before do
      allow( event_bus ).to receive(:test_case_started)
      allow( text ).to receive(:empty?)
    end

    context "reporting the duration of a test case" do
      before do
        allow( Timer::MonotonicTime ).to receive(:time_in_nanoseconds).and_return(525702744080000, 525702744080001)
      end

      context "for a passing test case" do
        let(:test_steps) { [passing] }

        it "records the nanoseconds duration of the execution on the result" do
          expect(event_bus).to receive(:test_case_finished) do |reported_test_case, result|
            expect( result.duration ).to be_duration 1
          end
          test_case.describe_to runner
        end
      end

      context "for a failing test case" do
        let(:test_steps) { [failing] }

        it "records the duration" do
          expect(event_bus).to receive(:test_case_finished) do |reported_test_case, result|
            expect(result.duration).to be_duration 1
          end
          test_case.describe_to runner
        end
      end
    end

    context "reporting the exception that failed a test case" do
      let(:test_steps) { [failing] }
      it "sets the exception on the result" do
        allow(event_bus).to receive(:before_test_case)
        expect(event_bus).to receive(:test_case_finished) do |reported_test_case, result|
          expect( result.exception ).to eq exception
        end
        test_case.describe_to runner
      end
    end

    context "with a single case" do
      context "without steps" do
        let(:test_steps) { [] }

        it "emits a test_case_started event before running the test case" do
          expect(event_bus).to receive(:test_case_started).with(test_case)
          test_case.describe_to runner
        end

        it "emits the test_case_finished event after running the the test case" do
          expect(event_bus).to receive(:test_case_finished) do |reported_test_case, result|
            expect( reported_test_case ).to eq test_case
            expect( result ).to be_undefined
          end
          test_case.describe_to runner
        end
      end

      context 'with steps' do
        context 'that all pass' do
          let(:test_steps) { [ passing, passing ]  }

          it 'emits the test_case_finished event with a passing result' do
            expect(event_bus).to receive(:test_case_finished) do |test_case, result|
              expect( result ).to be_passed
            end
            test_case.describe_to runner
          end
        end

        context 'an undefined step' do
          let(:test_steps) { [ undefined ]  }

          it 'emits the test_case_finished event with an undefined result' do
            expect(event_bus).to receive(:test_case_finished) do |test_case, result|
              expect( result ).to be_undefined
            end

            test_case.describe_to runner
          end

          it 'sets the message on the result' do
            expect(event_bus).to receive(:test_case_finished) do |test_case, result|
              expect( result.message ).to eq("Undefined step: \"step name\"")
            end
            allow( undefined ).to receive(:text).and_return('step name')

            test_case.describe_to runner
          end

          it 'appends the backtrace of the result' do
            expect(event_bus).to receive(:test_case_finished) do |test_case, result|
              expect( result.backtrace ).to eq(["step line"])
            end
            expect( undefined ).to receive(:backtrace_line).and_return('step line')

            test_case.describe_to runner
          end
        end

        context 'a pending step' do
          let(:test_steps) { [ pending ] }

          it 'emits the test_case_finished event with a pending result' do
            expect(event_bus).to receive(:test_case_finished) do |test_case, result|
              expect( result ).to be_pending
            end
            test_case.describe_to runner
          end

          it 'appends the backtrace of the result' do
            expect(event_bus).to receive(:test_case_finished) do |test_case, result|
              expect( result.backtrace.last ).to eq("step line")
            end
            expect( pending ).to receive(:backtrace_line).and_return('step line')

            test_case.describe_to runner
          end
        end

        context "a skipping step" do
          let(:test_steps) { [skipping] }

          it "emits the test_case_finished event with a skipped result" do
            expect(event_bus).to receive(:test_case_finished) do |test_case, result|
              expect( result ).to be_skipped
            end
            test_case.describe_to runner
          end

          it 'appends the backtrace of the result' do
            expect(event_bus).to receive(:test_case_finished) do |test_case, result|
              expect( result.backtrace.last ).to eq("step line")
            end
            expect( skipping ).to receive(:backtrace_line).and_return('step line')

            test_case.describe_to runner
          end
        end

        context 'that fail' do
          let(:test_steps) { [ failing ] }

          it 'emits the test_case_finished event with a failing result' do
            expect(event_bus).to receive(:test_case_finished) do |test_case, result|
              expect( result ).to be_failed
            end
            test_case.describe_to runner
          end

          it 'appends the backtrace of the exception of the result' do
            expect(event_bus).to receive(:test_case_finished) do |test_case, result|
              expect( result.exception.backtrace.last ).to eq("step line")
            end
            expect( failing ).to receive(:backtrace_line).and_return('step line')

            test_case.describe_to runner
          end
        end

        context 'where the first step fails' do
          let(:test_steps) { [ failing, passing ] }

          it 'emits the test_step_finished event with a failed result' do
            expect(event_bus).to receive(:test_step_finished).with(failing, anything) do |test_step, result|
              expect( result ).to be_failed
            end
            test_case.describe_to runner
          end

          it 'emits a test_step_finished event with a skipped result' do
            expect(event_bus).to receive(:test_step_finished).with(passing, anything) do |test_step, result|
              expect( result ).to be_skipped
            end
            test_case.describe_to runner
          end

          it 'emits a test_case_finished event with a failed result' do
            expect(event_bus).to receive(:test_case_finished) do |test_case, result|
              expect( result ).to be_failed
              expect( result.exception ).to eq exception
            end
            test_case.describe_to runner
          end

          it 'skips, rather than executing the second step' do
            expect( passing ).not_to receive(:execute)
            expect( passing ).to receive(:skip).and_return(Result::Skipped.new)
            test_case.describe_to runner
          end
        end

      end
    end

    context 'with multiple test cases' do
      context 'when the first test case fails' do
        let(:first_test_case) { Case.new(test_id, name, [failing], location, tags, language) }
        let(:last_test_case)  { Case.new(test_id, name, [passing], location, tags, language) }
        let(:test_cases)      { [first_test_case, last_test_case] }

        it 'reports the results correctly for the following test case' do
          expect(event_bus).to receive(:test_case_finished) { |reported_test_case, result|
            expect(result).to be_failed if reported_test_case.equal?(first_test_case)
            expect(result).to be_passed if reported_test_case.equal?(last_test_case)
          }.twice

          test_cases.each { |c| c.describe_to runner }
        end
      end
    end

    context "passing latest result to a mapping" do
      it "passes a Failed result when the scenario is failing" do
        result_spy = nil
        hook_mapping = UnskippableAction.new do |last_result|
          result_spy = last_result
        end
        after_hook = HookStep.new(step_id, text, location, hook_mapping)
        failing_step = Step.new(step_id, text, location).with_action { fail }
        test_case = Case.new(test_id, name, [failing_step, after_hook], location, tags, language)
        test_case.describe_to runner
        expect(result_spy).to be_failed
      end
    end

    require 'cucumber/core/test/around_hook'
    context "with around hooks" do
      it "passes normally when around hooks don't fail" do
        around_hook = AroundHook.new { |block| block.call }
        passing_step = Step.new(step_id, text, location, location).with_action {}
        test_case = Case.new(test_id, name, [passing_step], location, tags, language, [around_hook])
        expect(event_bus).to receive(:test_case_finished).with(test_case, anything) do |reported_test_case, result|
          expect(result).to be_passed
        end
        test_case.describe_to runner
      end

      it "gets a failed result if the Around hook fails before the test case is run" do
        around_hook = AroundHook.new { |block| raise exception }
        passing_step = Step.new(step_id, text, location, location).with_action {}
        test_case = Case.new(test_id, name, [passing_step], location, tags, language, [around_hook])
        expect(event_bus).to receive(:test_case_finished).with(test_case, anything) do |reported_test_case, result|
          expect(result).to be_failed
          expect(result.exception).to eq exception
        end
        test_case.describe_to runner
      end

      it "gets a failed result if the Around hook fails after the test case is run" do
        around_hook = AroundHook.new { |block| block.call; raise exception }
        passing_step = Step.new(step_id, text, location, location).with_action {}
        test_case = Case.new(test_id, name, [passing_step], location, tags, language, [around_hook])
        expect(event_bus).to receive(:test_case_finished).with(test_case, anything) do |reported_test_case, result|
          expect(result).to be_failed
          expect(result.exception).to eq exception
        end
        test_case.describe_to runner
      end

      it "fails when a step fails if the around hook works" do
        around_hook = AroundHook.new { |block| block.call }
        failing_step = Step.new(step_id, text, location, location).with_action { raise exception }
        test_case = Case.new(test_id, name, [failing_step], location, tags, language, [around_hook])
        expect(event_bus).to receive(:test_case_finished).with(test_case, anything) do |reported_test_case, result|
          expect(result).to be_failed
          expect(result.exception).to eq exception
        end
        test_case.describe_to runner
      end

      it "sends after_test_step for a step interrupted by (a timeout in) the around hook" do
        around_hook = AroundHook.new { |block| block.call; raise exception }
        passing_step = Step.new(step_id, text, location, location).with_action {}
        test_case = Case.new(test_id, name, [], location, tags, language, [around_hook])
        allow(runner).to receive(:running_test_step).and_return(passing_step)
        expect(event_bus).to receive(:test_step_finished).with(passing_step, anything) do |reported_test_case, result|
          expect(result).to be_failed
          expect(result.exception).to eq exception
        end
        expect(event_bus).to receive(:test_case_finished).with(test_case, anything) do |reported_test_case, result|
          expect(result).to be_failed
          expect(result.exception).to eq exception
        end
        test_case.describe_to runner
      end
    end

  end
end
