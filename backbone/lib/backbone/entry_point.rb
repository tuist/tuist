# frozen_string_literal: true
require 'backbone'

module Backbone
  module EntryPoint
    def self.call(args)
      cmd, command_name, args = Backbone::Resolver.call(args)
      Backbone::Executor.call(cmd, command_name, args)
    end
  end
end
