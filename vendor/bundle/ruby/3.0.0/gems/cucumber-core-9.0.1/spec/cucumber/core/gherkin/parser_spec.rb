# -*- encoding: utf-8 -*-
# frozen_string_literal: true
require 'cucumber/core/gherkin/parser'
require 'cucumber/core/gherkin/writer'

module Cucumber
  module Core
    module Gherkin
      describe Parser do
        let(:receiver)  { double }
        let(:event_bus) { double }
        let(:gherkin_query) { double }
        let(:parser)    { Parser.new(receiver, event_bus, gherkin_query) }
        let(:visitor)   { double }

        before do
          allow( event_bus ).to receive(:gherkin_source_parsed)
          allow( event_bus).to receive(:envelope)
          allow( gherkin_query ).to receive(:update)
        end

        def parse
          parser.document(source)
        end

        context "for invalid gherkin" do
          let(:source) { Gherkin::Document.new(path, "\nnot gherkin\n\nFeature: \n") }
          let(:path)   { 'path_to/the.feature' }

          it "raises an error" do
            expect { parse }.to raise_error(ParseError) do |error|
              expect( error.message ).to match(/not gherkin/)
              expect( error.message ).to match(/#{path}/)
            end
          end
        end

        context "for valid gherkin" do
          let(:source) { Gherkin::Document.new(path, 'Feature:') }
          let(:path)   { 'path_to/the.feature' }

          it "issues a gherkin_source_parsed event" do
            expect( event_bus ).to receive(:gherkin_source_parsed)
            parse
          end

          it "emits an 'envelope' event for every message produced by Gherkin" do
            # Only one message emited, there's no pickles generated
            expect( event_bus ).to receive(:envelope).once
            parse
          end
        end

        context "for empty files" do
          let(:source) { Gherkin::Document.new(path, '') }
          let(:path)   { 'path_to/the.feature' }

          it "passes on no pickles" do
            expect( receiver ).not_to receive(:pickle)
            parse
          end
        end

        include Writer
        def self.source(&block)
          let(:source) { gherkin(&block) }
        end

        RSpec::Matchers.define :pickle_with_language do |language|
          match { |actual| actual.language == language }
        end

        context "when the Gherkin has a language header" do
          source do
            feature(language: 'ja', keyword: '機能') do
              scenario(keyword: 'シナリオ')
            end
          end

          it "the pickles have the correct language" do
            expect( receiver ).to receive(:pickle).with(pickle_with_language('ja'))
            parse
          end
        end

        context "when the Gherkin produces one pickle" do
          source do
            feature do
              scenario do
                step 'text'
              end
            end
          end

          it "passes on the pickle" do
            expect( receiver ).to receive(:pickle)
            parse
          end

          it "emits an 'envelope' event containing the pickle" do
            allow( receiver ).to receive(:pickle)
            # Once for the gherkin document, once with the pickle
            expect( event_bus ).to receive(:envelope).twice
            parse
          end
        end

        context "when scenario is inside a rule" do
          source do
            feature do
              rule do
                scenario name: "My scenario"
              end
            end
          end

          it "passes on the pickle" do
            expect( receiver ).to receive(:pickle)
            parse
          end
        end

        context "when example is inside a rule" do
          source do
            feature do
              rule do
                example name: "My example"
              end
            end
          end

          it "passes on the pickle" do
            expect( receiver ).to receive(:pickle)
            parse
          end
        end

        context "when there are multiple rules and scenarios or examples" do
          source do
            feature do
              rule description: "First rule" do
                scenario name: "Do not talk about the fight club" do
                  step 'text'
                end
              end
              rule description: "Second rule" do
                example name: "Do not talk about the fight club" do
                  step 'text'
                end
              end
            end
          end

          it "passes on the pickles" do
            expect( receiver ).to receive(:pickle).twice
            parse
          end
        end
      end
    end
  end
end
