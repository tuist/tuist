# frozen_string_literal: true
module Fourier
  module Commands
    class GitHub < Base
      desc "cancel-workflows SUBCOMMAND ...ARGS", "Cancels all the running workflows"
      def cancel_workflows
        Services::GitHub::CancelWorkflows.call
      end
    end
  end
end
