require 'rspec'
require 'gherkin'
require 'gherkin/query'

describe Gherkin::Query do
  let(:subject) { Gherkin::Query.new() }

  def filter_messages_by_attribute(messages, attribute)
    messages.map do |message|
      return unless message.respond_to?(attribute)
      message.send(attribute)
    end.compact
  end

  def find_message_by_attribute(messages, attribute)
    filter_messages_by_attribute(messages, attribute).first
  end

  let(:gherkin_document) { find_message_by_attribute(messages, :gherkin_document) }

  let(:messages) {
    Gherkin.from_source(
      "some/path",
      feature_content,
      {
        include_gherkin_document: true
      }
    ).to_a
  }

  let(:feature_content) {
    """
    @feature-tag
    Feature: my feature

      Background:
        Given a passed background step

      @scenario-tag
      Scenario: my scenario
        Given a passed step

      Scenario Outline: with examples
        Given a <Status> step

        @example-tag
        Examples:
          | Status |
          | passed |


      Rule: this is a rule
        Background:
          Given the passed step in the rule background

        @ruled-scenario-tag
        Scenario: a ruled scenario
          Given a step in the ruled scenario
      """
  }

  context '#update' do
    context 'when the feature file is empty' do
      let(:feature_content) { '' }

      it 'does not fail' do
        expect {
          messages.each { |message|
            subject.update(message)
          }
        }.not_to raise_exception
      end
    end
  end

  context '#location' do
    before do
      messages.each { |message|
        subject.update(message)
      }
    end

    let(:background) { find_message_by_attribute(gherkin_document.feature.children, :background) }
    let(:scenarios) { filter_messages_by_attribute(gherkin_document.feature.children, :scenario) }
    let(:scenario) { scenarios.first }

    it 'raises an exception when the AST node ID is unknown' do
      expect { subject.location("this-id-may-not-exist-for-real") }.to raise_exception(Gherkin::AstNodeNotLocatedException)
    end

    it 'provides the location of a scenario' do
      expect(subject.location(scenario.id)).to eq(scenario.location)
    end

    it 'provides the location of an examples table row' do
      node = scenarios.last.examples.first.table_body.first
      expect(subject.location(node.id)).to eq(node.location)
    end

    context 'when querying steps' do
      let(:background_step) { background.steps.first }
      let(:scenario_step) { scenario.steps.first }

      it 'provides the location of a background step' do
        expect(subject.location(background_step.id)).to eq(background_step.location)
      end

      it 'provides the location of a scenario step' do
        expect(subject.location(scenario_step.id)).to eq(scenario_step.location)
      end
    end

    context 'when querying tags' do
      let(:feature_tag) { gherkin_document.feature.tags.first }
      let(:scenario_tag) { scenario.tags.first }
      let(:example_tag) { scenarios.last.examples.first.tags.first }

      it 'provides the location of a feature tags' do
        expect(subject.location(feature_tag.id)).to eq(feature_tag.location)
      end

      it 'provides the location of a scenario tags' do
        expect(subject.location(scenario_tag.id)).to eq(scenario_tag.location)
      end

      it 'provides the location of a scenario example tags' do
        expect(subject.location(example_tag.id)).to eq(example_tag.location)
      end
    end

    context 'when children are scoped in a Rule' do
      let(:rule) { find_message_by_attribute(gherkin_document.feature.children, :rule) }
      let(:rule_background) { find_message_by_attribute(rule.children, :background) }
      let(:rule_background_step) { rule_background.steps.first }
      let(:rule_scenario) { find_message_by_attribute(rule.children, :scenario) }
      let(:rule_scenario_step) { rule_scenario.steps.first }
      let(:rule_scenario_tag) { rule_scenario.tags.first }

      it 'provides the location of a background step' do
        expect(subject.location(rule_background_step.id)).to eq(rule_background_step.location)
      end

      it 'provides the location of a scenario' do
        expect(subject.location(rule_scenario.id)).to eq(rule_scenario.location)
      end

      it 'provides the location of a scenario tag' do
        expect(subject.location(rule_scenario_tag.id)).to eq(rule_scenario_tag.location)
      end

      it 'provides the location of a scenario step' do
        expect(subject.location(rule_scenario_step.id)).to eq(rule_scenario_step.location)
      end
    end
  end
end