# encoding: utf-8

##
# This file is auto-generated. DO NOT EDIT!
#
require 'protobuf'

module Cucumber
  module Messages
    ::Protobuf::Optionable.inject(self) { ::Google::Protobuf::FileOptions }

    ##
    # Message Classes
    #
    class Envelope < ::Protobuf::Message; end
    class Meta < ::Protobuf::Message
      class Product < ::Protobuf::Message; end
      class CI < ::Protobuf::Message
        class Git < ::Protobuf::Message; end

      end


    end

    class Timestamp < ::Protobuf::Message; end
    class Duration < ::Protobuf::Message; end
    class Location < ::Protobuf::Message; end
    class SourceReference < ::Protobuf::Message
      class JavaMethod < ::Protobuf::Message; end
      class JavaStackTraceElement < ::Protobuf::Message; end

    end

    class Source < ::Protobuf::Message; end
    class GherkinDocument < ::Protobuf::Message
      class Comment < ::Protobuf::Message; end
      class Feature < ::Protobuf::Message
        class Tag < ::Protobuf::Message; end
        class FeatureChild < ::Protobuf::Message
          class Rule < ::Protobuf::Message; end
          class RuleChild < ::Protobuf::Message; end

        end

        class Background < ::Protobuf::Message; end
        class Scenario < ::Protobuf::Message
          class Examples < ::Protobuf::Message; end

        end

        class TableRow < ::Protobuf::Message
          class TableCell < ::Protobuf::Message; end

        end

        class Step < ::Protobuf::Message
          class DataTable < ::Protobuf::Message; end
          class DocString < ::Protobuf::Message; end

        end


      end


    end

    class Attachment < ::Protobuf::Message
      class ContentEncoding < ::Protobuf::Enum
        define :IDENTITY, 0
        define :BASE64, 1
      end

    end

    class Pickle < ::Protobuf::Message
      class PickleTag < ::Protobuf::Message; end
      class PickleStep < ::Protobuf::Message; end

    end

    class PickleStepArgument < ::Protobuf::Message
      class PickleDocString < ::Protobuf::Message; end
      class PickleTable < ::Protobuf::Message
        class PickleTableRow < ::Protobuf::Message
          class PickleTableCell < ::Protobuf::Message; end

        end


      end


    end

    class TestCase < ::Protobuf::Message
      class TestStep < ::Protobuf::Message
        class StepMatchArgumentsList < ::Protobuf::Message
          class StepMatchArgument < ::Protobuf::Message
            class Group < ::Protobuf::Message; end

          end


        end


      end


    end

    class TestRunStarted < ::Protobuf::Message; end
    class TestCaseStarted < ::Protobuf::Message; end
    class TestCaseFinished < ::Protobuf::Message; end
    class TestStepStarted < ::Protobuf::Message; end
    class TestStepFinished < ::Protobuf::Message
      class TestStepResult < ::Protobuf::Message
        class Status < ::Protobuf::Enum
          define :UNKNOWN, 0
          define :PASSED, 1
          define :SKIPPED, 2
          define :PENDING, 3
          define :UNDEFINED, 4
          define :AMBIGUOUS, 5
          define :FAILED, 6
        end

      end


    end

    class TestRunFinished < ::Protobuf::Message; end
    class Hook < ::Protobuf::Message; end
    class StepDefinition < ::Protobuf::Message
      class StepDefinitionPattern < ::Protobuf::Message
        class StepDefinitionPatternType < ::Protobuf::Enum
          define :CUCUMBER_EXPRESSION, 0
          define :REGULAR_EXPRESSION, 1
        end

      end


    end

    class ParameterType < ::Protobuf::Message; end
    class UndefinedParameterType < ::Protobuf::Message; end
    class ParseError < ::Protobuf::Message; end


    ##
    # File Options
    #
    set_option :go_package, "messages"


    ##
    # Message Fields
    #
    class Envelope
      optional ::Cucumber::Messages::Source, :source, 1
      optional ::Cucumber::Messages::GherkinDocument, :gherkin_document, 2
      optional ::Cucumber::Messages::Pickle, :pickle, 3
      optional ::Cucumber::Messages::StepDefinition, :step_definition, 4
      optional ::Cucumber::Messages::Hook, :hook, 5
      optional ::Cucumber::Messages::ParameterType, :parameter_type, 6
      optional ::Cucumber::Messages::TestCase, :test_case, 7
      optional ::Cucumber::Messages::UndefinedParameterType, :undefined_parameter_type, 8
      optional ::Cucumber::Messages::TestRunStarted, :test_run_started, 9
      optional ::Cucumber::Messages::TestCaseStarted, :test_case_started, 10
      optional ::Cucumber::Messages::TestStepStarted, :test_step_started, 11
      optional ::Cucumber::Messages::Attachment, :attachment, 12
      optional ::Cucumber::Messages::TestStepFinished, :test_step_finished, 13
      optional ::Cucumber::Messages::TestCaseFinished, :test_case_finished, 14
      optional ::Cucumber::Messages::TestRunFinished, :test_run_finished, 15
      optional ::Cucumber::Messages::ParseError, :parse_error, 16
      optional ::Cucumber::Messages::Meta, :meta, 17
    end

    class Meta
      class Product
        optional :string, :name, 1
        optional :string, :version, 2
      end

      class CI
        class Git
          optional :string, :remote, 1
          optional :string, :revision, 2
          optional :string, :branch, 3
          optional :string, :tag, 4
        end

        optional :string, :name, 1
        optional :string, :url, 2
        optional ::Cucumber::Messages::Meta::CI::Git, :git, 3
      end

      optional :string, :protocol_version, 1
      optional ::Cucumber::Messages::Meta::Product, :implementation, 2
      optional ::Cucumber::Messages::Meta::Product, :runtime, 3
      optional ::Cucumber::Messages::Meta::Product, :os, 4
      optional ::Cucumber::Messages::Meta::Product, :cpu, 5
      optional ::Cucumber::Messages::Meta::CI, :ci, 6
    end

    class Timestamp
      optional :int64, :seconds, 1
      optional :int32, :nanos, 2
    end

    class Duration
      optional :int64, :seconds, 1
      optional :int32, :nanos, 2
    end

    class Location
      optional :uint32, :line, 1
      optional :uint32, :column, 2
    end

    class SourceReference
      class JavaMethod
        optional :string, :class_name, 1
        optional :string, :method_name, 2
        repeated :string, :method_parameter_types, 3
      end

      class JavaStackTraceElement
        optional :string, :class_name, 1
        optional :string, :method_name, 2
        optional :string, :file_name, 3
      end

      optional :string, :uri, 1
      optional ::Cucumber::Messages::SourceReference::JavaMethod, :java_method, 3
      optional ::Cucumber::Messages::SourceReference::JavaStackTraceElement, :java_stack_trace_element, 4
      optional ::Cucumber::Messages::Location, :location, 2
    end

    class Source
      optional :string, :uri, 1
      optional :string, :data, 2
      optional :string, :media_type, 3
    end

    class GherkinDocument
      class Comment
        optional ::Cucumber::Messages::Location, :location, 1
        optional :string, :text, 2
      end

      class Feature
        class Tag
          optional ::Cucumber::Messages::Location, :location, 1
          optional :string, :name, 2
          optional :string, :id, 3
        end

        class FeatureChild
          class Rule
            optional ::Cucumber::Messages::Location, :location, 1
            optional :string, :keyword, 2
            optional :string, :name, 3
            optional :string, :description, 4
            repeated ::Cucumber::Messages::GherkinDocument::Feature::FeatureChild::RuleChild, :children, 5
            optional :string, :id, 6
            repeated ::Cucumber::Messages::GherkinDocument::Feature::Tag, :tags, 7
          end

          class RuleChild
            optional ::Cucumber::Messages::GherkinDocument::Feature::Background, :background, 1
            optional ::Cucumber::Messages::GherkinDocument::Feature::Scenario, :scenario, 2
          end

          optional ::Cucumber::Messages::GherkinDocument::Feature::FeatureChild::Rule, :rule, 1
          optional ::Cucumber::Messages::GherkinDocument::Feature::Background, :background, 2
          optional ::Cucumber::Messages::GherkinDocument::Feature::Scenario, :scenario, 3
        end

        class Background
          optional ::Cucumber::Messages::Location, :location, 1
          optional :string, :keyword, 2
          optional :string, :name, 3
          optional :string, :description, 4
          repeated ::Cucumber::Messages::GherkinDocument::Feature::Step, :steps, 5
          optional :string, :id, 6
        end

        class Scenario
          class Examples
            optional ::Cucumber::Messages::Location, :location, 1
            repeated ::Cucumber::Messages::GherkinDocument::Feature::Tag, :tags, 2
            optional :string, :keyword, 3
            optional :string, :name, 4
            optional :string, :description, 5
            optional ::Cucumber::Messages::GherkinDocument::Feature::TableRow, :table_header, 6
            repeated ::Cucumber::Messages::GherkinDocument::Feature::TableRow, :table_body, 7
            optional :string, :id, 8
          end

          optional ::Cucumber::Messages::Location, :location, 1
          repeated ::Cucumber::Messages::GherkinDocument::Feature::Tag, :tags, 2
          optional :string, :keyword, 3
          optional :string, :name, 4
          optional :string, :description, 5
          repeated ::Cucumber::Messages::GherkinDocument::Feature::Step, :steps, 6
          repeated ::Cucumber::Messages::GherkinDocument::Feature::Scenario::Examples, :examples, 7
          optional :string, :id, 8
        end

        class TableRow
          class TableCell
            optional ::Cucumber::Messages::Location, :location, 1
            optional :string, :value, 2
          end

          optional ::Cucumber::Messages::Location, :location, 1
          repeated ::Cucumber::Messages::GherkinDocument::Feature::TableRow::TableCell, :cells, 2
          optional :string, :id, 3
        end

        class Step
          class DataTable
            optional ::Cucumber::Messages::Location, :location, 1
            repeated ::Cucumber::Messages::GherkinDocument::Feature::TableRow, :rows, 2
          end

          class DocString
            optional ::Cucumber::Messages::Location, :location, 1
            optional :string, :media_type, 2
            optional :string, :content, 3
            optional :string, :delimiter, 4
          end

          optional ::Cucumber::Messages::Location, :location, 1
          optional :string, :keyword, 2
          optional :string, :text, 3
          optional ::Cucumber::Messages::GherkinDocument::Feature::Step::DocString, :doc_string, 4
          optional ::Cucumber::Messages::GherkinDocument::Feature::Step::DataTable, :data_table, 5
          optional :string, :id, 6
        end

        optional ::Cucumber::Messages::Location, :location, 1
        repeated ::Cucumber::Messages::GherkinDocument::Feature::Tag, :tags, 2
        optional :string, :language, 3
        optional :string, :keyword, 4
        optional :string, :name, 5
        optional :string, :description, 6
        repeated ::Cucumber::Messages::GherkinDocument::Feature::FeatureChild, :children, 7
      end

      optional :string, :uri, 1
      optional ::Cucumber::Messages::GherkinDocument::Feature, :feature, 2
      repeated ::Cucumber::Messages::GherkinDocument::Comment, :comments, 3
    end

    class Attachment
      optional ::Cucumber::Messages::SourceReference, :source, 1
      optional :string, :test_step_id, 2
      optional :string, :test_case_started_id, 3
      optional :string, :body, 4
      optional :string, :media_type, 5
      optional ::Cucumber::Messages::Attachment::ContentEncoding, :content_encoding, 6
      optional :string, :file_name, 7
      optional :string, :url, 8
    end

    class Pickle
      class PickleTag
        optional :string, :name, 1
        optional :string, :ast_node_id, 2
      end

      class PickleStep
        optional :string, :text, 1
        optional ::Cucumber::Messages::PickleStepArgument, :argument, 2
        optional :string, :id, 3
        repeated :string, :ast_node_ids, 4
      end

      optional :string, :id, 1
      optional :string, :uri, 2
      optional :string, :name, 3
      optional :string, :language, 4
      repeated ::Cucumber::Messages::Pickle::PickleStep, :steps, 5
      repeated ::Cucumber::Messages::Pickle::PickleTag, :tags, 6
      repeated :string, :ast_node_ids, 7
    end

    class PickleStepArgument
      class PickleDocString
        optional :string, :media_type, 1
        optional :string, :content, 2
      end

      class PickleTable
        class PickleTableRow
          class PickleTableCell
            optional :string, :value, 1
          end

          repeated ::Cucumber::Messages::PickleStepArgument::PickleTable::PickleTableRow::PickleTableCell, :cells, 1
        end

        repeated ::Cucumber::Messages::PickleStepArgument::PickleTable::PickleTableRow, :rows, 1
      end

      optional ::Cucumber::Messages::PickleStepArgument::PickleDocString, :doc_string, 1
      optional ::Cucumber::Messages::PickleStepArgument::PickleTable, :data_table, 2
    end

    class TestCase
      class TestStep
        class StepMatchArgumentsList
          class StepMatchArgument
            class Group
              optional :uint32, :start, 1
              optional :string, :value, 2
              repeated ::Cucumber::Messages::TestCase::TestStep::StepMatchArgumentsList::StepMatchArgument::Group, :children, 3
            end

            optional :string, :parameter_type_name, 1
            optional ::Cucumber::Messages::TestCase::TestStep::StepMatchArgumentsList::StepMatchArgument::Group, :group, 2
          end

          repeated ::Cucumber::Messages::TestCase::TestStep::StepMatchArgumentsList::StepMatchArgument, :step_match_arguments, 1
        end

        optional :string, :id, 1
        optional :string, :pickle_step_id, 2
        repeated :string, :step_definition_ids, 3
        repeated ::Cucumber::Messages::TestCase::TestStep::StepMatchArgumentsList, :step_match_arguments_lists, 4
        optional :string, :hook_id, 5
      end

      optional :string, :id, 1
      optional :string, :pickle_id, 2
      repeated ::Cucumber::Messages::TestCase::TestStep, :test_steps, 3
    end

    class TestRunStarted
      optional ::Cucumber::Messages::Timestamp, :timestamp, 1
    end

    class TestCaseStarted
      optional ::Cucumber::Messages::Timestamp, :timestamp, 1
      optional :uint32, :attempt, 3
      optional :string, :test_case_id, 4
      optional :string, :id, 5
    end

    class TestCaseFinished
      optional ::Cucumber::Messages::Timestamp, :timestamp, 1
      optional :string, :test_case_started_id, 3
    end

    class TestStepStarted
      optional ::Cucumber::Messages::Timestamp, :timestamp, 1
      optional :string, :test_step_id, 2
      optional :string, :test_case_started_id, 3
    end

    class TestStepFinished
      class TestStepResult
        optional ::Cucumber::Messages::TestStepFinished::TestStepResult::Status, :status, 1
        optional :string, :message, 2
        optional ::Cucumber::Messages::Duration, :duration, 3
        optional :bool, :will_be_retried, 4
      end

      optional ::Cucumber::Messages::TestStepFinished::TestStepResult, :test_step_result, 1
      optional ::Cucumber::Messages::Timestamp, :timestamp, 2
      optional :string, :test_step_id, 3
      optional :string, :test_case_started_id, 4
    end

    class TestRunFinished
      optional :bool, :success, 1
      optional ::Cucumber::Messages::Timestamp, :timestamp, 2
      optional :string, :message, 3
    end

    class Hook
      optional :string, :id, 1
      optional :string, :tag_expression, 2
      optional ::Cucumber::Messages::SourceReference, :source_reference, 3
    end

    class StepDefinition
      class StepDefinitionPattern
        optional :string, :source, 1
        optional ::Cucumber::Messages::StepDefinition::StepDefinitionPattern::StepDefinitionPatternType, :type, 2
      end

      optional :string, :id, 1
      optional ::Cucumber::Messages::StepDefinition::StepDefinitionPattern, :pattern, 2
      optional ::Cucumber::Messages::SourceReference, :source_reference, 3
    end

    class ParameterType
      optional :string, :name, 1
      repeated :string, :regular_expressions, 2
      optional :bool, :prefer_for_regular_expression_match, 3
      optional :bool, :use_for_snippets, 4
      optional :string, :id, 5
    end

    class UndefinedParameterType
      optional :string, :name, 1
      optional :string, :expression, 2
    end

    class ParseError
      optional ::Cucumber::Messages::SourceReference, :source, 1
      optional :string, :message, 2
    end

  end

end

