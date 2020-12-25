# frozen_string_literal: true
require 'backbone'

module Backbone
  module Commands
    # No point in using autoload/autocall here; it's loaded immediately by
    # `register` calls.
    Registry = CLI::Kit::CommandRegistry.new(
      default: 'help',
      contextual_resolver: nil
    )

    def self.register(const, cmd, path)
      autoload(const, path)
      Registry.add(->() { const_get(const) }, cmd)
    end

    register :Test, 'test', 'backbone/commands/test'
  end
end
