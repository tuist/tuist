# frozen_string_literal: true

module Fourier
  module Commands
    class Encrypt < Base
      desc "secrets", "Encrypt the secrets in this repository"
      def secrets
        Services::Encrypt::Secrets.call
      end
    end
  end
end
