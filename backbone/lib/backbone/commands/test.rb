# frozen_string_literal: true
require 'backbone'
require 'json'

module Backbone
  module Commands
    class Test < Backbone::Command
      def call(_args, _name)
        puts "Running tests"
      end

      def self.help
        "Run Tuist tests"
      end
    end
  end
end
