# frozen_string_literal: true

require 'cucumber/constantize'
require 'cucumber/runtime/for_programming_languages'
require 'cucumber/runtime/step_hooks'
require 'cucumber/runtime/before_hooks'
require 'cucumber/runtime/after_hooks'
require 'cucumber/gherkin/steps_parser'
require 'cucumber/step_match_search'

module Cucumber
  class Runtime
    class SupportCode
      require 'forwardable'
      class StepInvoker
        def initialize(support_code)
          @support_code = support_code
        end

        def steps(steps)
          steps.each { |step| step(step) }
        end

        def step(step)
          location = Core::Test::Location.of_caller
          @support_code.invoke_dynamic_step(step[:text], multiline_arg(step, location))
        end

        def multiline_arg(step, location)
          if !step[:doc_string].nil?
            MultilineArgument.from(step[:doc_string][:content], location, step[:doc_string][:content_type])
          elsif !step[:data_table].nil?
            MultilineArgument::DataTable.from(step[:data_table][:rows].map { |row| row[:cells].map { |cell| cell[:value] } })
          else
            MultilineArgument.from(nil)
          end
        end
      end

      include Constantize

      attr_reader :registry

      def initialize(user_interface, configuration = Configuration.default)
        @configuration = configuration
        # TODO: needs a better name, or inlining its methods
        @runtime_facade = Runtime::ForProgrammingLanguages.new(self, user_interface)
        @registry = Cucumber::Glue::RegistryAndMore.new(@runtime_facade, @configuration)
      end

      def configure(new_configuration)
        @configuration = Configuration.new(new_configuration)
      end

      # Invokes a series of steps +steps_text+. Example:
      #
      #   invoke(%Q{
      #     Given I have 8 cukes in my belly
      #     Then I should not be thirsty
      #   })
      def invoke_dynamic_steps(steps_text, iso_code, _location)
        parser = Cucumber::Gherkin::StepsParser.new(StepInvoker.new(self), iso_code)
        parser.parse(steps_text)
      end

      # @api private
      # This allows users to attempt to find, match and execute steps
      # from code as the features are running, as opposed to regular
      # steps which are compiled into test steps before execution.
      #
      # These are commonly called nested steps.
      def invoke_dynamic_step(step_name, multiline_argument, _location = nil)
        matches = step_matches(step_name)
        raise UndefinedDynamicStep, step_name if matches.empty?
        matches.first.invoke(multiline_argument)
      end

      def load_files!(files)
        log.debug("Code:\n")
        files.each do |file|
          load_file(file)
        end
        log.debug("\n")
      end

      def load_files_from_paths(paths)
        files = paths.map { |path| Dir["#{path}/**/*.rb"] }.flatten
        load_files! files
      end

      def unmatched_step_definitions
        registry.unmatched_step_definitions
      end

      def fire_hook(name, *args)
        # TODO: kill with fire
        registry.send(name, *args)
      end

      def step_definitions
        registry.step_definitions
      end

      def find_after_step_hooks(test_case)
        scenario = RunningTestCase.new(test_case)
        hooks = registry.hooks_for(:after_step, scenario)
        StepHooks.new(@configuration.id_generator, hooks, @configuration.event_bus)
      end

      def apply_before_hooks(test_case)
        return test_case if test_case.test_steps.empty?
        scenario = RunningTestCase.new(test_case)
        hooks = registry.hooks_for(:before, scenario)
        BeforeHooks.new(@configuration.id_generator, hooks, scenario, @configuration.event_bus).apply_to(test_case)
      end

      def apply_after_hooks(test_case)
        return test_case if test_case.test_steps.empty?
        scenario = RunningTestCase.new(test_case)
        hooks = registry.hooks_for(:after, scenario)
        AfterHooks.new(@configuration.id_generator, hooks, scenario, @configuration.event_bus).apply_to(test_case)
      end

      def find_around_hooks(test_case)
        scenario = RunningTestCase.new(test_case)

        registry.hooks_for(:around, scenario).map do |hook|
          Hooks.around_hook do |run_scenario|
            hook.invoke('Around', scenario, &run_scenario)
          end
        end
      end

      private

      def step_matches(step_name)
        StepMatchSearch.new(registry.method(:step_matches), @configuration).call(step_name)
      end

      def load_file(file)
        log.debug("  * #{file}\n")
        registry.load_code_file(file)
      end

      def log
        Cucumber.logger
      end
    end
  end
end
