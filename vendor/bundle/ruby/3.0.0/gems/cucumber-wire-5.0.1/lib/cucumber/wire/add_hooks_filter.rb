# coding: utf-8
require 'cucumber/messages'

module Cucumber
  module Wire
    class AddHooksFilter < Core::Filter.new(:connections)
      def test_case(test_case)
        test_case.
          with_steps([before_hook(test_case)] + test_case.test_steps + [after_hook(test_case)]).
          describe_to receiver
      end

      def before_hook(test_case)
        # TODO: is this dependency on Cucumber::Hooks OK? Feels a bit internal..
        # TODO: how do we express the location of the hook? Should we create one hook per connection so we can use the host:port of the connection?
        Cucumber::Hooks.before_hook(id_generator.new_id, Core::Test::Location.new('TODO:wire')) do
          connections.begin_scenario(test_case)
        end
      end

      def after_hook(test_case)
        Cucumber::Hooks.after_hook(id_generator.new_id, Core::Test::Location.new('TODO:wire')) do
          connections.end_scenario(test_case)
        end
      end

      def id_generator
        @id_generator ||= Cucumber::Messages::IdGenerator::UUID.new
      end
    end
  end
end
