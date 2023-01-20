# frozen_string_literal: true

module Fourier
  module Services
    class Fixture < Base
      attr_reader :path, :projects, :targets, :sources

      def initialize(path:, projects:, targets:, sources:)
        @path = path
        @projects = projects
        @targets = targets
        @sources = sources
      end

      def call
        arguments = [
          "--path",
path,
          "--projects",
projects.to_s,
          "--targets",
targets.to_s,
          "--sources",
sources.to_s,
        ]
        Utilities::System.fixturegen(*arguments)
      end
    end
  end
end
