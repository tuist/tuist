# encoding: utf-8
# frozen_string_literal: true
require 'cucumber/core/gherkin/writer'
require 'cucumber/core'
require 'cucumber/core/test/filters/locations_filter'
require 'timeout'
require 'cucumber/core/test/location'

module Cucumber::Core
  describe Test::LocationsFilter do
    include Cucumber::Core::Gherkin::Writer
    include Cucumber::Core

    let(:receiver) { SpyReceiver.new }

    let(:doc) do
      gherkin('features/test.feature') do
        feature do
          scenario 'x' do
            step 'a step'
          end

          scenario 'y' do
            step 'a step'
          end
        end
      end
    end

    it "sorts by the given locations" do
      locations = [
        Test::Location.new('features/test.feature', 6),
        Test::Location.new('features/test.feature', 3)
      ]
      filter = Test::LocationsFilter.new(locations)
      compile [doc], receiver, [filter]
      expect(receiver.test_case_locations).to eq locations
    end

    it "works with wildcard locations" do
      locations = [
        Test::Location.new('features/test.feature')
      ]
      filter = Test::LocationsFilter.new(locations)
      compile [doc], receiver, [filter]
      expect(receiver.test_case_locations).to eq [
        Test::Location.new('features/test.feature', 3),
        Test::Location.new('features/test.feature', 6)
      ]
    end

    it "filters out scenarios that don't match" do
      locations = [
        Test::Location.new('features/test.feature', 3)
      ]
      filter = Test::LocationsFilter.new(locations)
      compile [doc], receiver, [filter]
      expect(receiver.test_case_locations).to eq locations
    end

    describe "matching location" do
      let(:file) { 'features/path/to/the.feature' }

      let(:test_cases) do
        receiver = double.as_null_object
        result = []
        allow(receiver).to receive(:test_case) { |test_case| result << test_case }
        compile [doc], receiver
        result
      end

      context "for a scenario" do
        let(:doc) do
          Gherkin::Document.new(file, <<-END)
            Feature:

              Scenario: one
                Given one a

              # comment
              @tags
              Scenario: two
                Given two a
                And two b

              Scenario: three
                Given three b

              Scenario: with docstring
                Given a docstring
                  """
                  this is a docstring
                  """

              Scenario: with a table
                Given a table
                  | a | b |
                  | 1 | 2 |
                  | 3 | 4 |

          END
        end

        def test_case_named(name)
          test_cases.find { |c| c.name == name }
        end

        it 'matches the precise location of the scenario' do
          location = test_case_named('two').location
          filter = Test::LocationsFilter.new([location])
          compile [doc], receiver, [filter]
          expect(receiver.test_case_locations).to eq [test_case_named('two').location]
        end

        it 'matches multiple locations' do
          good_location = Test::Location.new(file, 8)
          bad_location = Test::Location.new(file, 5)
          filter = Test::LocationsFilter.new([good_location, bad_location])
          compile [doc], receiver, [filter]
          expect(receiver.test_case_locations).to eq [test_case_named('two').location]
        end

        it "doesn't match a location after the scenario line" do
          location = Test::Location.new(file, 9)
          filter = Test::LocationsFilter.new([location])
          compile [doc], receiver, [filter]
          expect(receiver.test_case_locations).to eq []
        end

        it "doesn't match a location before the scenario line" do
          location = Test::Location.new(file, 7)
          filter = Test::LocationsFilter.new([location])
          compile [doc], receiver, [filter]
          expect(receiver.test_case_locations).to eq []
        end

        context "with duplicate locations in the filter" do
          it "matches each test case only once" do
            location_tc_two = test_case_named('two').location
            location_tc_one = test_case_named('one').location
            location_last_step_tc_two = Test::Location.new(file, 10)
            filter = Test::LocationsFilter.new([location_tc_two, location_tc_one, location_last_step_tc_two])
            compile [doc], receiver, [filter]
            expect(receiver.test_case_locations).to eq [test_case_named('two').location, location_tc_one = test_case_named('one').location]
          end
        end
      end

      context "for a scenario outline" do
        let(:doc) do
          Gherkin::Document.new(file, <<-END)
            Feature:

              Scenario: one
                Given one a

              # comment on line 6
              @tags-on-line-7
              Scenario Outline: two <arg>
                Given two a
                And two <arg>
                  """
                  docstring
                  """

                # comment on line 15
                @tags-on-line-16
                Examples: x1
                  | arg |
                  | b   |

                Examples: x2
                  | arg |
                  | c   |
                  | d   |

              Scenario: three
                Given three b
          END
        end

        let(:test_case) do
          test_cases.find { |c| c.name == "two b" }
        end

        it "matches row location to the test case of the row" do
          locations = [
            Test::Location.new(file, 19),
          ]
          filter = Test::LocationsFilter.new(locations)
          compile [doc], receiver, [filter]
          expect(receiver.test_case_locations).to eq [test_case.location]
        end

        it "matches outline location with the all test cases of all the tables" do
          locations = [
            Test::Location.new(file, 8),
          ]
          filter = Test::LocationsFilter.new(locations)
          compile [doc], receiver, [filter]
          expect(receiver.test_case_locations.map(&:line)).to eq [19, 23, 24]
        end

        it "doesn't match the location of the examples line" do
          location = Test::Location.new(file, 17)
          filter = Test::LocationsFilter.new([location])
          compile [doc], receiver, [filter]
          expect(receiver.test_case_locations).to eq []
        end
      end
    end

    context "under load", slow: true do
      num_features = 50
      num_scenarios_per_feature = 50

      let(:docs) do
        (1..num_features).map do |i|
          gherkin("features/test_#{i}.feature") do
            feature do
              (1..num_scenarios_per_feature).each do |j|
                scenario "scenario #{j}" do
                  step 'text'
                end
              end
            end
          end
        end
      end

      num_locations = num_features
      let(:locations) do
        (1..num_locations).map do |i|
          (1..num_scenarios_per_feature).map do |j|
            line = 3 + (j - 1) * 3
            Test::Location.new("features/test_#{i}.feature", line)
          end
        end.flatten
      end

      max_duration_ms = 10000
      max_duration_ms = max_duration_ms * 2.5 if defined?(JRUBY_VERSION)
      it "filters #{num_features * num_scenarios_per_feature} test cases within #{max_duration_ms}ms" do
        filter = Test::LocationsFilter.new(locations)
        Timeout.timeout(max_duration_ms / 1000.0) do
          compile docs, receiver, [filter]
        end
        expect(receiver.test_cases.length).to eq num_features * num_scenarios_per_feature
      end

    end
  end

  class SpyReceiver
    def test_case(test_case)
      test_cases << test_case
    end

    def done
    end

    def test_case_locations
      test_cases.map(&:location)
    end

    def test_cases
      @test_cases ||= []
    end

  end
end
