# frozen_string_literal: true
module Fourier
  module Services
    module Generate
      class Fixture < Base
        attr_reader :path, :projects, :targets, :sources

        def initialize(path:, projects:, targets:, sources:)
          @path = path
          @projects = projects
          @targets = targets
          @sources = sources
        end

        def call
          Dir.chdir(fixturegen_directory) do
            arguments = [
              "swift", "run", "fixturegen",
              "--path", path,
              "--projects", projects.to_s,
              "--targets", targets.to_s,
              "--sources", sources.to_s
            ]
            Utilities::System.system(*arguments)
          end
        end
      end
    end
  end
end
