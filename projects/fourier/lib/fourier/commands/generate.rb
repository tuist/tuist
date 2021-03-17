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
    end
  end
end
