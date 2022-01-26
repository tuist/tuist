require 'base64'
require 'cucumber/formatter/backtrace_filter'
require 'cucumber/formatter/query/hook_by_test_step'
require 'cucumber/formatter/query/pickle_by_test'
require 'cucumber/formatter/query/pickle_step_by_test_step'
require 'cucumber/formatter/query/step_definitions_by_test_step'
require 'cucumber/formatter/query/test_case_started_by_test_case'

module Cucumber
  module Formatter
    class MessageBuilder
      include Cucumber::Messages::TimeConversion

      def initialize(config)
        @config = config

        @hook_by_test_step = Query::HookByTestStep.new(config)
        @pickle_by_test = Query::PickleByTest.new(config)
        @pickle_step_by_test_step = Query::PickleStepByTestStep.new(config)
        @step_definitions_by_test_step = Query::StepDefinitionsByTestStep.new(config)
        @test_case_started_by_test_case = Query::TestCaseStartedByTestCase.new(config)

        config.on_event :envelope, &method(:on_envelope)
        config.on_event :gherkin_source_read, &method(:on_gherkin_source_read)
        config.on_event :test_case_ready, &method(:on_test_case_ready)
        config.on_event :test_run_started, &method(:on_test_run_started)
        config.on_event :test_case_started, &method(:on_test_case_started)
        config.on_event :test_step_started, &method(:on_test_step_started)
        config.on_event :test_step_finished, &method(:on_test_step_finished)
        config.on_event :test_case_finished, &method(:on_test_case_finished)
        config.on_event :test_run_finished, &method(:on_test_run_finished)
        config.on_event :undefined_parameter_type, &method(:on_undefined_parameter_type)

        @test_case_by_step_id = {}
        @current_test_case_started_id = nil
        @current_test_step_id = nil
      end

      def output_message
        raise 'To be implemented'
      end

      def attach(src, media_type)
        attachment_data = {
          test_step_id: @current_test_step_id,
          test_case_started_id: @current_test_case_started_id,
          media_type: media_type
        }

        if media_type.start_with?('text/')
          attachment_data[:content_encoding] = Cucumber::Messages::Attachment::ContentEncoding::IDENTITY
          attachment_data[:body] = src
        else
          body = src.respond_to?(:read) ? src.read : src

          attachment_data[:content_encoding] = Cucumber::Messages::Attachment::ContentEncoding::BASE64
          attachment_data[:body] = Base64.strict_encode64(body)
        end

        message = Cucumber::Messages::Envelope.new(
          attachment: Cucumber::Messages::Attachment.new(**attachment_data)
        )

        output_envelope(message)
      end

      private

      def on_envelope(event)
        output_envelope(event.envelope)
      end

      def on_gherkin_source_read(event)
        message = Cucumber::Messages::Envelope.new(
          source: Cucumber::Messages::Source.new(
            uri: event.path,
            data: event.body,
            media_type: 'text/x.cucumber.gherkin+plain'
          )
        )

        output_envelope(message)
      end

      def on_test_case_ready(event)
        event.test_case.test_steps.each do |step|
          @test_case_by_step_id[step.id] = event.test_case
        end

        message = Cucumber::Messages::Envelope.new(
          test_case: Cucumber::Messages::TestCase.new(
            id: event.test_case.id,
            pickle_id: @pickle_by_test.pickle_id(event.test_case),
            test_steps: event.test_case.test_steps.map { |step| test_step_to_message(step) }
          )
        )

        output_envelope(message)
      end

      def test_step_to_message(step)
        return hook_step_to_message(step) if step.hook?

        Cucumber::Messages::TestCase::TestStep.new(
          id: step.id,
          pickle_step_id: @pickle_step_by_test_step.pickle_step_id(step),
          step_definition_ids: @step_definitions_by_test_step.step_definition_ids(step),
          step_match_arguments_lists: step_match_arguments_lists(step)
        )
      end

      def hook_step_to_message(step)
        Cucumber::Messages::TestCase::TestStep.new(
          id: step.id,
          hook_id: @hook_by_test_step.hook_id(step)
        )
      end

      def step_match_arguments_lists(step)
        match_arguments = step_match_arguments(step)
        [Cucumber::Messages::TestCase::TestStep::StepMatchArgumentsList.new(
          step_match_arguments: match_arguments
        )]
      rescue Cucumber::Formatter::TestStepUnknownError
        []
      end

      def step_match_arguments(step)
        @step_definitions_by_test_step.step_match_arguments(step).map do |argument|
          Cucumber::Messages::TestCase::TestStep::StepMatchArgumentsList::StepMatchArgument.new(
            group: argument_group_to_message(argument.group),
            parameter_type_name: argument.parameter_type.name
          )
        end
      end

      def argument_group_to_message(group)
        Cucumber::Messages::TestCase::TestStep::StepMatchArgumentsList::StepMatchArgument::Group.new(
          start: group.start,
          value: group.value,
          children: group.children.map { |child| argument_group_to_message(child) }
        )
      end

      def on_test_run_started(*)
        message = Cucumber::Messages::Envelope.new(
          test_run_started: Cucumber::Messages::TestRunStarted.new(
            timestamp: time_to_timestamp(Time.now)
          )
        )

        output_envelope(message)
      end

      def on_test_case_started(event)
        @current_test_case_started_id = test_case_started_id(event.test_case)

        message = Cucumber::Messages::Envelope.new(
          test_case_started: Cucumber::Messages::TestCaseStarted.new(
            id: test_case_started_id(event.test_case),
            test_case_id: event.test_case.id,
            timestamp: time_to_timestamp(Time.now),
            attempt: @test_case_started_by_test_case.attempt_by_test_case(event.test_case)
          )
        )

        output_envelope(message)
      end

      def on_test_step_started(event)
        @current_test_step_id = event.test_step.id
        test_case = @test_case_by_step_id[event.test_step.id]

        message = Cucumber::Messages::Envelope.new(
          test_step_started: Cucumber::Messages::TestStepStarted.new(
            test_step_id: event.test_step.id,
            test_case_started_id: test_case_started_id(test_case),
            timestamp: time_to_timestamp(Time.now)
          )
        )

        output_envelope(message)
      end

      def on_test_step_finished(event)
        test_case = @test_case_by_step_id[event.test_step.id]
        result = event
                 .result
                 .with_filtered_backtrace(Cucumber::Formatter::BacktraceFilter)

        result_message = result.to_message
        if result.failed? || result.pending?
          result_message = Cucumber::Messages::TestStepFinished::TestStepResult.new(
            status: result_message.status,
            duration: result_message.duration,
            message: create_error_message(result)
          )
        end

        message = Cucumber::Messages::Envelope.new(
          test_step_finished: Cucumber::Messages::TestStepFinished.new(
            test_step_id: event.test_step.id,
            test_case_started_id: test_case_started_id(test_case),
            test_step_result: result_message,
            timestamp: time_to_timestamp(Time.now)
          )
        )

        output_envelope(message)
      end

      def create_error_message(result)
        message_element = result.failed? ? result.exception : result
        message = "#{message_element.message} (#{message_element.class})"
        ([message] + message_element.backtrace).join("\n")
      end

      def on_test_case_finished(event)
        message = Cucumber::Messages::Envelope.new(
          test_case_finished: Cucumber::Messages::TestCaseFinished.new(
            test_case_started_id: test_case_started_id(event.test_case),
            timestamp: time_to_timestamp(Time.now)
          )
        )

        output_envelope(message)
      end

      def on_test_run_finished(*)
        message = Cucumber::Messages::Envelope.new(
          test_run_finished: Cucumber::Messages::TestRunFinished.new(
            timestamp: time_to_timestamp(Time.now)
          )
        )

        output_envelope(message)
      end

      def on_undefined_parameter_type(event)
        message = Cucumber::Messages::Envelope.new(
          undefined_parameter_type: Cucumber::Messages::UndefinedParameterType.new(
            name: event.type_name,
            expression: event.expression
          )
        )

        output_envelope(message)
      end

      def test_case_started_id(test_case)
        @test_case_started_by_test_case.test_case_started_id_by_test_case(test_case)
      end
    end
  end
end
