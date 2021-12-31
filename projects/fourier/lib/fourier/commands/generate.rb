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
        :targets,
        desc: "The list of targets to focus",
        default: [],
        type: :array,
        aliases: :t
      )
      def tuist
        Services::Generate::Tuist.call(open: options[:open], targets: options[:targets])
      end
    end
  end
end
