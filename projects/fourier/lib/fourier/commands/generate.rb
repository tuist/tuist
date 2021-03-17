# frozen_string_literal: true
module Fourier
  module Commands
    class Generate < Base
      desc "tuist", "Generate the XcodeProj for Tuist"
      option(
        :open,
        desc: "Whether the project should be opened in Xcode after generating it",
        default: false,
        type: :boolean,
        aliases: :o
      )
      def tuist
        Services::Generate::Tuist.call(open: options[:open])
      end

      desc "fixture", "Generate a fixture Tuist project"
      option(
        :path,
        desc: "The path to the directory where the fixture will be generated",
        type: :string,
        required: true,
        aliases: :p
      )
      option(
        :projects,
        desc: "The number of projects to generate",
        type: :numeric,
        required: true,
        aliases: :P
      )
      option(
        :targets,
        desc: "The number of targets to generate",
        type: :numeric,
        required: true,
        aliases: :t
      )
      option(
        :sources,
        desc: "The number of sources to generate",
        type: :numeric,
        required: true,
        aliases: :s
      )
      def fixture
        Services::Generate::Fixture.call(
          path: options[:path],
          projects: options[:projects],
          targets: options[:targets],
          sources: options[:sources]
        )
      end
    end
  end
end
