# frozen_string_literal: true

module Fourier
  module Commands
    class Edit < Base
      desc "tuist", "Edit the Tuist's project manifest"
      def tuist
        Services::Edit::Tuist.call
      end
    end
  end
end
