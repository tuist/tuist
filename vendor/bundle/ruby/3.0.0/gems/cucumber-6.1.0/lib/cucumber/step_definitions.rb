# frozen_string_literal: true

module Cucumber
  class StepDefinitions
    def initialize(configuration = Configuration.default)
      configuration = Configuration.new(configuration)
      @support_code = Runtime::SupportCode.new(nil, configuration)
      @support_code.load_files_from_paths(configuration.autoload_code_paths)
    end

    def to_json(obj = nil)
      @support_code.step_definitions.map(&:to_hash).to_json(obj)
    end
  end
end
