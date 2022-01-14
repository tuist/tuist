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
      option(
        :source,
        desc: "Builds Tuist from source to generate the project",
        default: false,
        type: :boolean
      )
      def tuist
        Services::Generate::Tuist.call(open: options[:open], source: options[:source])
      end
    end
  end
end
