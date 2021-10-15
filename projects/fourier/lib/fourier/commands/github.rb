# frozen_string_literal: true

module Fourier
  module Commands
    class GitHub < Base
      desc "cancel-workflows SUBCOMMAND ...ARGS", "Cancels all the running workflows"
      def cancel_workflows
        Utilities::Secrets.decrypt
        Services::GitHub::CancelWorkflows.call
      end
    end
  end
end
