# frozen_string_literal: true
require 'report_api_spy'
require 'cucumber/core'
require 'cucumber/core/filter'
require 'cucumber/core/gherkin/writer'
require 'cucumber/core/platform'
require 'cucumber/core/report/summary'
require 'cucumber/core/test/around_hook'
require 'cucumber/core/test/filters/activate_steps_for_self_test'

module Cucumber
  describe Core do
    include Core
    include Core::Gherkin::Writer

    describe "compiling features to a test suite" do

      it "compiles two scenarios into two test cases" do
        visitor = ReportAPISpy.new

        compile([
          gherkin do
            feature do
              background do
                step 'text'
              end
              scenario do
                step 'text'
              end
              scenario do
                step 'text'
                step 'text'
              end
            end
          end
        ], visitor)

        expect( visitor.messages ).to eq [
          :test_case,
          :test_step,
          :test_step,
          :test_case,
          :test_step,
          :test_step,
          :test_step,
          :done,
        ]
      end

      it "filters out test cases based on a tag expression" do
        visitor = double.as_null_object
        expect( visitor ).to receive(:test_case) do |test_case|
          expect( test_case.name ).to eq 'foo'
        end.exactly(1).times

        gherkin = gherkin do
          feature do
            scenario tags: '@b' do
              step 'text'
            end

            scenario_outline 'foo' do
              step '<arg>'

              examples tags: '@a' do
                row 'arg'
                row 'x'
              end

              examples 'bar', tags: '@a @b' do
                row 'arg'
                row 'y'
              end
            end
          end
        end

        compile [gherkin], visitor, [Cucumber::Core::Test::TagFilter.new(['@a', '@b'])]
      end
    end

    describe "executing a test suite" do

      it "fires events" do
        gherkin = gherkin do
          feature 'Feature name' do
            scenario 'The one that passes' do
              step 'passing'
            end

            scenario 'The one that fails' do
              step 'passing'
              step 'failing'
              step 'passing'
              step 'undefined'
            end
          end
        end

        observed_events = []
        execute [gherkin], [Core::Test::Filters::ActivateStepsForSelfTest.new] do |event_bus|
          event_bus.on(:test_case_started) do |event|
            test_case = event.test_case
            observed_events << [:test_case_started, test_case.name]
          end
          event_bus.on(:test_case_finished) do |event|
            test_case, result = *event.attributes
            observed_events << [:test_case_finished, test_case.name, result.to_sym]
          end
          event_bus.on(:test_step_started) do |event|
            test_step = event.test_step
            observed_events << [:test_step_started, test_step.text]
          end
          event_bus.on(:test_step_finished) do |event|
            test_step, result = *event.attributes
            observed_events << [:test_step_finished, test_step.text, result.to_sym]
          end
        end

        expect(observed_events).to eq [
          [:test_case_started, 'The one that passes'],
          [:test_step_started, 'passing'],
          [:test_step_finished, 'passing', :passed],
          [:test_case_finished, 'The one that passes', :passed],
          [:test_case_started, 'The one that fails'],
          [:test_step_started, 'passing'],
          [:test_step_finished, 'passing', :passed],
          [:test_step_started, 'failing'],
          [:test_step_finished, 'failing', :failed],
          [:test_step_started, 'passing'],
          [:test_step_finished, 'passing', :skipped],
          [:test_step_started, 'undefined'],
          [:test_step_finished, 'undefined', :undefined],
          [:test_case_finished, 'The one that fails', :failed],
        ]
      end

      context "without hooks" do
        it "executes the test cases in the suite" do
          gherkin = gherkin do
            feature 'Feature name' do
              scenario 'The one that passes' do
                step 'passing'
              end

              scenario 'The one that fails' do
                step 'passing'
                step 'failing'
                step 'passing'
                step 'undefined'
              end
            end
          end

          event_bus = Core::EventBus.new
          report = Core::Report::Summary.new(event_bus)
          execute [gherkin], [Core::Test::Filters::ActivateStepsForSelfTest.new], event_bus

          expect( report.test_cases.total           ).to eq 2
          expect( report.test_cases.total_passed    ).to eq 1
          expect( report.test_cases.total_failed    ).to eq 1
          expect( report.test_steps.total           ).to eq 5
          expect( report.test_steps.total_failed    ).to eq 1
          expect( report.test_steps.total_passed    ).to eq 2
          expect( report.test_steps.total_skipped   ).to eq 1
          expect( report.test_steps.total_undefined ).to eq 1
        end
      end

      context "with around hooks" do
        class WithAroundHooks < Core::Filter.new(:logger)
          def test_case(test_case)
            base_step = Core::Test::Step.new('some-random-uid', 'text', nil, nil, nil)
            test_steps = [
              base_step.with_action { logger << :step },
            ]

            around_hook = Core::Test::AroundHook.new do |run_scenario|
              logger << :before_all
              run_scenario.call
              logger << :middle
              run_scenario.call
              logger << :after_all
            end
            test_case.with_steps(test_steps).with_around_hooks([around_hook]).describe_to(receiver)
          end
        end

        it "executes the test cases in the suite" do
          gherkin = gherkin do
            feature do
              scenario do
                step 'text'
              end
            end
          end
          logger = []

          event_bus = Core::EventBus.new
          report = Core::Report::Summary.new(event_bus)
          execute [gherkin], [WithAroundHooks.new(logger)], event_bus

          expect( report.test_cases.total        ).to eq 1
          expect( report.test_cases.total_passed ).to eq 1
          expect( report.test_cases.total_failed ).to eq 0
          expect( logger ).to eq [
            :before_all,
              :step,
            :middle,
              :step,
            :after_all
          ]
        end
      end

      require 'cucumber/core/test/filters'
      it "filters test cases by tag" do
        gherkin = gherkin do
          feature do
            scenario do
              step 'text'
            end

            scenario tags: '@a @b' do
              step 'text'
            end

            scenario tags: '@a' do
              step 'text'
            end
          end
        end

        event_bus = Core::EventBus.new
        report = Core::Report::Summary.new(event_bus)
        execute [gherkin], [ Cucumber::Core::Test::TagFilter.new(['@a']) ], event_bus

        expect( report.test_cases.total ).to eq 2
      end

      it "filters test cases by name" do
        gherkin = gherkin do
          feature 'first feature' do
            scenario 'first scenario' do
              step 'missing'
            end
            scenario 'second' do
              step 'missing'
            end
          end
        end

        event_bus = Core::EventBus.new
        report = Core::Report::Summary.new(event_bus)
        execute [gherkin], [ Cucumber::Core::Test::NameFilter.new([/scenario/]) ], event_bus

        expect( report.test_cases.total ).to eq 1
      end

    end
  end
end
