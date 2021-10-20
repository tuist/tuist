# frozen_string_literal: true

module Fourier
  module Services
    module GitHub
      class CancelWorkflows < Base
        attr_reader :github_client

        def initialize(github_client: Utilities::GitHubClient.new)
          @github_client = github_client
        end

        def call
          runs = github_client.repository_workflow_runs(Constants::REPOSITORY, { status: "queued" })
          runs[:workflow_runs].each do |run|
            puts "Cancelling workflow run with id: #{run[:id]}"
            github_client.cancel_workflow_run(Constants::REPOSITORY, run[:id])
          end
        end
      end
    end
  end
end
