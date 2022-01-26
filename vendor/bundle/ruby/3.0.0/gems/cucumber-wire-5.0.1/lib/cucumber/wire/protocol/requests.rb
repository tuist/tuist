# coding: utf-8
require 'cucumber/wire/request_handler'
require 'cucumber/wire/step_argument'

module Cucumber
  module Wire
    module Protocol
      module Requests
        class StepMatches < RequestHandler
          def execute(name_to_match)
            @name_to_match = name_to_match
            request_params = {
              :name_to_match => name_to_match
            }
            super(request_params)
          end

          def handle_success(params)
            params.map do |raw_step_match|
              create_step_match(raw_step_match)
            end
          end

          alias :handle_step_matches :handle_success

          private

          def create_step_match(raw_step_match)
            step_definition = StepDefinition.new(@connection, raw_step_match, @registry)
            step_args = raw_step_match['args'].map do |raw_arg|
              StepArgument.new(raw_arg['pos'], raw_arg['val'])
            end
            step_match(step_definition, step_args)
          end

          def step_match(step_definition, step_args)
            StepMatch.new(step_definition, @name_to_match, step_args)
          end
        end

        class SnippetText < RequestHandler
          def execute(step_keyword, step_name, multiline_arg_class_name)
            request_params = {
              :step_keyword => step_keyword,
              :step_name => step_name,
              :multiline_arg_class => multiline_arg_class_name
            }
            super(request_params)
          end

          def handle_success(snippet_text)
            snippet_text
          end

          alias :handle_snippet_text :handle_success
        end

        class Invoke < RequestHandler
          def execute(step_definition_id, args)
            request_params = {
              :id => step_definition_id,
              :args => args
            }
            super(request_params)
          end

          def handle_pending(message)
            raise Pending, message || "TODO"
          end

          def handle_diff!(tables)
            table1 = table(tables[0])
            table2 = table(tables[1])
            table1.diff!(table2)
          end

          def handle_diff(tables)
            begin
              handle_diff!(tables)
            rescue Cucumber::MultilineArgument::DataTable::Different
              @connection.diff_failed
            end
            @connection.diff_ok
          end

          alias :handle_step_failed :handle_fail

          private

          def table(data)
            Cucumber::MultilineArgument.from_core(Core::Test::DataTable.new(data))
          end
        end

        class DiffFailed < RequestHandler
          alias :handle_step_failed :handle_fail
        end

        class DiffOk < RequestHandler
          alias :handle_step_failed :handle_fail
        end

        class HookRequestHandler < RequestHandler
          def execute(test_case)
            super(request_params(test_case))
          end

          private

          def request_params(test_case)
            return nil unless test_case.tags.any?
            { "tags" => clean_tag_names(test_case.tags) }
          end

          def clean_tag_names(tags)
            tags.map { |tag| tag.name.gsub(/^@/, '') }.sort
          end
        end

        BeginScenario = Class.new(HookRequestHandler)

        EndScenario = Class.new(HookRequestHandler)

      end
    end
  end
end
