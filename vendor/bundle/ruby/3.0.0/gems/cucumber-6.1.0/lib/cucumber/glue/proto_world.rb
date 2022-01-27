# frozen_string_literal: true

require 'cucumber/gherkin/formatter/ansi_escapes'
require 'cucumber/core/test/data_table'
require 'cucumber/deprecate'
require 'mime/types'

module Cucumber
  module Glue
    # Defines the basic API methods availlable in all Cucumber step definitions.
    #
    # You can, and probably should, extend this API with your own methods that
    # make sense in your domain. For more on that, see {Cucumber::Glue::Dsl#World}
    module ProtoWorld
      # Run a single Gherkin step
      # @example Call another step
      #   step "I am logged in"
      # @example Call a step with quotes in the name
      #   step %{the user "Dave" is logged in}
      # @example Passing a table
      #   step "the following users exist:", table(%{
      #     | name  | email           |
      #     | Matt  | matt@matt.com   |
      #     | Aslak | aslak@aslak.com |
      #   })
      # @example Passing a multiline string
      #   step "the email should contain:", "Dear sir,\nYou've won a prize!\n"
      # @param [String] name The name of the step
      # @param [String,Cucumber::Test::DocString,Cucumber::Ast::Table] multiline_argument
      def step(name, raw_multiline_arg = nil)
        super
      end

      # Run a snippet of Gherkin
      # @example
      #   steps %{
      #     Given the user "Susan" exists
      #     And I am logged in as "Susan"
      #   }
      # @param [String] steps_text The Gherkin snippet to run
      def steps(steps_text)
        super
      end

      # Parse Gherkin into a {Cucumber::Ast::Table} object.
      #
      # Useful in conjunction with the #step method.
      # @example Create a table
      #   users = table(%{
      #     | name  | email           |
      #     | Matt  | matt@matt.com   |
      #     | Aslak | aslak@aslak.com |
      #   })
      # @param [String] text_or_table The Gherkin string that represents the table
      # Returns a Cucumber::MultilineArgument::DataTable for +text_or_table+, which can either
      # be a String:
      #
      #   table(%{
      #     | account | description | amount |
      #     | INT-100 | Taxi        | 114    |
      #     | CUC-101 | Peeler      | 22     |
      #   })
      #
      # or a 2D Array:
      #
      #   table([
      #     %w{ account description amount },
      #     %w{ INT-100 Taxi        114    },
      #     %w{ CUC-101 Peeler      22     }
      #   ])
      #
      def table(text_or_table)
        MultilineArgument::DataTable.from(text_or_table)
      end

      # Pause the tests and ask the operator for input
      def ask(question, timeout_seconds = 60)
        super
      end

      def log(*messages)
        messages.each { |message| attach(message.to_s.dup, 'text/x.cucumber.log+plain') }
      end

      # Attach a file to the output
      # @param file [string|io] the file to attach.
      #   It can be a string containing the file content itself,
      #   the file path, or an IO ready to be read.
      # @param media_type [string] the media type. If file is a valid path,
      #   media_type can be ommitted, it will then be inferred from the file name.
      def attach(file, media_type = nil)
        return super unless File.file?(file)

        content = File.read(file, mode: 'rb')
        media_type = MIME::Types.type_for(file).first if media_type.nil?

        super(content, media_type.to_s)
      rescue StandardError
        super
      end

      # Mark the matched step as pending.
      def pending(message = 'TODO')
        raise Pending, message unless block_given?

        begin
          yield
        rescue Exception # rubocop:disable Lint/RescueException
          raise Pending, message
        end
        raise Pending, "Expected pending '#{message}' to fail. No Error was raised. No longer pending?"
      end

      # Skips this step and the remaining steps in the scenario
      def skip_this_scenario(message = 'Scenario skipped')
        raise Core::Test::Result::Skipped, message
      end

      # Prints the list of modules that are included in the World
      def inspect
        super
      end

      # see {#inspect}
      def to_s
        inspect
      end

      # Dynamially generate the API module, closuring the dependencies
      def self.for(runtime, language) # rubocop:disable Metrics/MethodLength,Metrics/AbcSize
        Module.new do # rubocop:disable Metrics/BlockLength
          def self.extended(object)
            # wrap the dynamically generated module so that we can document the methods
            # for yardoc, which doesn't like define_method.
            object.extend(ProtoWorld)
          end

          # TODO: pass these in when building the module, instead of mutating them later
          # Extend the World with user-defined modules
          def add_modules!(world_modules, namespaced_world_modules)
            add_world_modules!(world_modules)
            add_namespaced_modules!(namespaced_world_modules)
          end

          define_method(:step) do |name, raw_multiline_arg = nil|
            location = Core::Test::Location.of_caller
            runtime.invoke_dynamic_step(name, MultilineArgument.from(raw_multiline_arg, location))
          end

          define_method(:steps) do |steps_text|
            location = Core::Test::Location.of_caller
            runtime.invoke_dynamic_steps(steps_text, language, location)
          end

          define_method(:ask) do |question, timeout_seconds = 60|
            runtime.ask(question, timeout_seconds)
          end

          define_method(:attach) do |file, media_type|
            runtime.attach(file, media_type)
          end

          # Prints the list of modules that are included in the World
          def inspect
            modules = [self.class]
            (class << self; self; end).instance_eval do
              modules += included_modules
            end
            modules << stringify_namespaced_modules
            format('#<%<modules>s:0x%<object_id>x>', modules: modules.join('+'), object_id: object_id)
          end

          private

          # @private
          def add_world_modules!(modules)
            modules.each do |world_module|
              extend(world_module)
            end
          end

          # @private
          def add_namespaced_modules!(modules)
            @__namespaced_modules = modules
            modules.each do |namespace, world_modules|
              world_modules.each do |world_module|
                variable_name = "@__#{namespace}_world"

                inner_world = if self.class.respond_to?(namespace)
                                instance_variable_get(variable_name)
                              else
                                Object.new
                              end
                instance_variable_set(variable_name,
                                      inner_world.extend(world_module))
                self.class.send(:define_method, namespace) do
                  instance_variable_get(variable_name)
                end
              end
            end
          end

          # @private
          def stringify_namespaced_modules
            @__namespaced_modules.map { |k, v| "#{v.join(',')} (as #{k})" }.join('+')
          end
        end
      end

      # @private
      AnsiEscapes = Cucumber::Gherkin::Formatter::AnsiEscapes
    end
  end
end
