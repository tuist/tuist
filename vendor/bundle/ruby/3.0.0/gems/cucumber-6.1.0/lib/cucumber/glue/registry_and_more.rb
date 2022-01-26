# frozen_string_literal: true

require 'cucumber/cucumber_expressions/parameter_type_registry'
require 'cucumber/cucumber_expressions/cucumber_expression'
require 'cucumber/cucumber_expressions/regular_expression'
require 'cucumber/cucumber_expressions/cucumber_expression_generator'
require 'cucumber/glue/dsl'
require 'cucumber/glue/snippet'
require 'cucumber/glue/hook'
require 'cucumber/glue/proto_world'
require 'cucumber/glue/step_definition'
require 'cucumber/glue/world_factory'
require 'cucumber/gherkin/i18n'
require 'multi_test'
require 'cucumber/step_match'
require 'cucumber/step_definition_light'
require 'cucumber/events/step_definition_registered'

module Cucumber
  module Glue
    # Raised if a World block returns Nil.
    class NilWorld < StandardError
      def initialize
        super('World procs should never return nil')
      end
    end

    # Raised if there are 2 or more World blocks.
    class MultipleWorld < StandardError
      def initialize(first_proc, second_proc)
        message = String.new # rubocop:disable Style/EmptyLiteral
        message << "You can only pass a proc to #World once, but it's happening\n"
        message << "in 2 places:\n\n"
        message << Glue.backtrace_line(first_proc, 'World') << "\n"
        message << Glue.backtrace_line(second_proc, 'World') << "\n\n"
        message << "Use Ruby modules instead to extend your worlds. See the Cucumber::Glue::Dsl#World RDoc\n"
        message << "or http://wiki.github.com/cucumber/cucumber/a-whole-new-world.\n\n"
        super(message)
      end
    end

    # TODO: This class has too many responsibilities, split off
    class RegistryAndMore
      attr_reader :current_world,
                  :step_definitions

      all_keywords = ::Gherkin::DIALECTS.keys.map do |dialect_name|
        dialect = ::Gherkin::Dialect.for(dialect_name)
        dialect.given_keywords + dialect.when_keywords + dialect.then_keywords + dialect.and_keywords + dialect.but_keywords
      end
      Cucumber::Gherkin::I18n.code_keywords_for(all_keywords.flatten.uniq.sort).each do |adverb|
        Glue::Dsl.alias_adverb(adverb.strip)
      end

      def initialize(runtime, configuration)
        @runtime = runtime
        @configuration = configuration
        @step_definitions = []
        Glue::Dsl.rb_language = self
        @world_proc = @world_modules = nil
        @parameter_type_registry = CucumberExpressions::ParameterTypeRegistry.new
        cucumber_expression_generator = CucumberExpressions::CucumberExpressionGenerator.new(@parameter_type_registry)
        @configuration.register_snippet_generator(Snippet::Generator.new(cucumber_expression_generator))
      end

      def step_matches(name_to_match)
        @step_definitions.each_with_object([]) do |step_definition, result|
          if (arguments = step_definition.arguments_from(name_to_match))
            result << StepMatch.new(step_definition, name_to_match, arguments)
          end
        end
      end

      def register_rb_hook(phase, tag_expressions, proc)
        hook = add_hook(phase, Hook.new(@configuration.id_generator.new_id, self, tag_expressions, proc))
        @configuration.notify :envelope, hook.to_envelope
        hook
      end

      def define_parameter_type(parameter_type)
        @configuration.notify :envelope, parameter_type_envelope(parameter_type)

        @parameter_type_registry.define_parameter_type(parameter_type)
      end

      def register_rb_step_definition(string_or_regexp, proc_or_sym, options)
        step_definition = StepDefinition.new(@configuration.id_generator.new_id, self, string_or_regexp, proc_or_sym, options)
        @step_definitions << step_definition
        @configuration.notify :step_definition_registered, step_definition
        @configuration.notify :envelope, step_definition.to_envelope
        step_definition
      rescue Cucumber::CucumberExpressions::UndefinedParameterTypeError => e
        # TODO: add a way to extract the parameter type directly from the error.
        type_name = e.message.match(/^Undefined parameter type ['|\{](.*)['|\}].?$/)[1]

        @configuration.notify :undefined_parameter_type, type_name, string_or_regexp
      end

      def build_rb_world_factory(world_modules, namespaced_world_modules, proc)
        if proc
          raise MultipleWorld.new(@world_proc, proc) if @world_proc
          @world_proc = proc
        end
        @world_modules ||= []
        @world_modules += world_modules

        @namespaced_world_modules ||= Hash.new { |h, k| h[k] = [] }
        namespaced_world_modules.each do |namespace, world_module|
          @namespaced_world_modules[namespace] << world_module unless @namespaced_world_modules[namespace].include?(world_module)
        end
      end

      def load_code_file(code_file)
        return unless File.extname(code_file) == '.rb'

        # This will cause self.add_step_definition, self.add_hook, and self.define_parameter_type to be called from Glue::Dsl

        if Cucumber.use_legacy_autoloader
          load File.expand_path(code_file)
        else
          require File.expand_path(code_file)
        end
      end

      def begin_scenario(test_case)
        @current_world = WorldFactory.new(@world_proc).create_world
        @current_world.extend(ProtoWorld.for(@runtime, test_case.language))
        MultiTest.extend_with_best_assertion_library(@current_world)
        @current_world.add_modules!(@world_modules || [],
                                    @namespaced_world_modules || {})
      end

      def end_scenario
        @current_world = nil
      end

      def after_configuration(configuration)
        hooks[:after_configuration].each do |hook|
          hook.invoke('AfterConfiguration', configuration)
        end
      end

      def add_hook(phase, hook)
        hooks[phase.to_sym] << hook
        hook
      end

      def clear_hooks
        @hooks = nil
      end

      def hooks_for(phase, scenario) #:nodoc:
        hooks[phase.to_sym].select { |hook| scenario.accept_hook?(hook) }
      end

      def unmatched_step_definitions
        available_step_definition_hash.keys - invoked_step_definition_hash.keys
      end

      def available_step_definition(regexp_source, file_colon_line)
        available_step_definition_hash[StepDefinitionLight.new(regexp_source, file_colon_line)] = nil
      end

      def invoked_step_definition(regexp_source, file_colon_line)
        invoked_step_definition_hash[StepDefinitionLight.new(regexp_source, file_colon_line)] = nil
      end

      def create_expression(string_or_regexp)
        return CucumberExpressions::CucumberExpression.new(string_or_regexp, @parameter_type_registry) if string_or_regexp.is_a?(String)
        return CucumberExpressions::RegularExpression.new(string_or_regexp, @parameter_type_registry) if string_or_regexp.is_a?(Regexp)
        raise ArgumentError, 'Expression must be a String or Regexp'
      end

      def self.cli_snippet_type_options
        registry = CucumberExpressions::ParameterTypeRegistry.new
        cucumber_expression_generator = CucumberExpressions::CucumberExpressionGenerator.new(registry)
        Snippet::SNIPPET_TYPES.keys.sort_by(&:to_s).map do |type|
          Snippet::SNIPPET_TYPES[type].cli_option_string(type, cucumber_expression_generator)
        end
      end

      private

      def parameter_type_envelope(parameter_type)
        # TODO: should me moved to Cucumber::Expression::ParameterType#to_envelope ?
        # Note: that would mean that cucumber-expression would depend on cucumber-messages

        Cucumber::Messages::Envelope.new(
          parameter_type: Cucumber::Messages::ParameterType.new(
            id: @configuration.id_generator.new_id,
            name: parameter_type.name,
            regular_expressions: parameter_type.regexps.map(&:to_s),
            prefer_for_regular_expression_match: parameter_type.prefer_for_regexp_match?,
            use_for_snippets: parameter_type.use_for_snippets?
          )
        )
      end

      def available_step_definition_hash
        @available_step_definition_hash ||= {}
      end

      def invoked_step_definition_hash
        @invoked_step_definition_hash ||= {}
      end

      def hooks
        @hooks ||= Hash.new { |h, k| h[k] = [] }
      end
    end

    def self.backtrace_line(proc, name)
      location = Cucumber::Core::Test::Location.from_source_location(*proc.source_location)
      "#{location}:in `#{name}'"
    end
  end
end
