# frozen_string_literal: true

module Fourier
  module Commands
    class Edit < Base
      desc "tuist", "Edit the Tuist's project manifest"
      option(
        :source,
        desc: "Builds Tuist from source and uses that binary to edit the project's manifest",
        default: false,
        type: :boolean
      )
      def tuist
        Services::Edit::Tuist.call(source: options[:source])
      end
    end
  end
end
