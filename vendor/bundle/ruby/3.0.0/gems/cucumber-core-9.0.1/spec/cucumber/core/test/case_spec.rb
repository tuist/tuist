# frozen_string_literal: true
# -*- coding: utf-8 -*-
require 'cucumber/core'
require 'cucumber/core/gherkin/writer'
require 'cucumber/core/platform'
require 'cucumber/core/test/case'
require 'unindent'

module Cucumber
  module Core
    module Test
      describe Case do
        include Core
        include Core::Gherkin::Writer

        let(:id) { double }
        let(:name) { double }
        let(:location) { double }
        let(:tags) { double }
        let(:language) { double }
        let(:test_case) { Test::Case.new(id, name, test_steps, location, tags, language) }
        let(:test_steps) { [double, double] }

        context 'describing itself' do
          it "describes itself to a visitor" do
            visitor = double
            args = double
            expect( visitor ).to receive(:test_case).with(test_case, args)
            test_case.describe_to(visitor, args)
          end

          it "asks each test_step to describe themselves to the visitor" do
            visitor = double
            args = double
            test_steps.each do |test_step|
              expect( test_step ).to receive(:describe_to).with(visitor, args)
            end
            allow( visitor ).to receive(:test_case).and_yield(visitor)
            test_case.describe_to(visitor, args)
          end

          it "describes around hooks in order" do
            visitor = double
            allow( visitor ).to receive(:test_case).and_yield(visitor)
            first_hook, second_hook = double, double
            expect( first_hook ).to receive(:describe_to).ordered.and_yield
            expect( second_hook ).to receive(:describe_to).ordered.and_yield
            around_hooks = [first_hook, second_hook]
            Test::Case.new(id, name, [], location, tags, language, around_hooks).describe_to(visitor, double)
          end

        end

        describe "#name" do
          it "the name is passed when creating the test case" do
            expect( test_case.name ).to eq(name)
          end
        end

        describe "#location" do
          it "the location is passed when creating the test case" do
            expect( test_case.location ).to eq(location)
          end
        end

        describe "#tags" do
          it "the tags are passed when creating the test case" do
            expect( test_case.tags ).to eq(tags)
          end
        end

        describe "matching tags" do
          let(:tags) { ['@a', '@b', '@c'].map { |value| Tag.new(location, value) } }
          it "matches tags using tag expressions" do
            expect( test_case.match_tags?(['@a and @b']) ).to be_truthy
            expect( test_case.match_tags?(['@a or @d']) ).to be_truthy
            expect( test_case.match_tags?(['not @d']) ).to be_truthy
            expect( test_case.match_tags?(['@a and @d']) ).to be_falsy
          end

          it "matches handles multiple expressions" do
            expect( test_case.match_tags?(['@a and @b', 'not @d']) ).to be_truthy
            expect( test_case.match_tags?(['@a and @b', 'not @c']) ).to be_falsy
          end
        end

        describe "matching names" do
          let(:name) { 'scenario' }
          it "matches names against regexp" do
            expect( test_case.match_name?(/scenario/) ).to be_truthy
          end
        end

        describe "#language" do
          let(:language) { 'en-pirate' }
          it "the language is passed when creating the test case" do
            expect( test_case.language ).to eq 'en-pirate'
          end
        end

        describe "equality" do
          it "is equal to another test case at the same location" do
            gherkin = gherkin('features/foo.feature') do
              feature do
                scenario do
                  step 'text'
                end
              end
            end
            test_case_instances = []
            receiver = double.as_null_object
            allow(receiver).to receive(:test_case) do |test_case|
              test_case_instances << test_case
            end
            2.times { compile([gherkin], receiver) }
            expect(test_case_instances.length).to eq 2
            expect(test_case_instances.uniq.length).to eq 1
            expect(test_case_instances[0]).to be_eql test_case_instances[1]
            expect(test_case_instances[0]).to eq test_case_instances[1]
            expect(test_case_instances[0]).not_to equal test_case_instances[1]
          end
        end

      end
    end
  end
end
