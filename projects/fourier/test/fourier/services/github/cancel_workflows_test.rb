# frozen_string_literal: true

require "test_helper"

module Fourier
  module Services
    module GitHub
      class CancelWorkflowsTest < TestCase
        def test_cancels_workflows
          # Given
          github_client = mock("github_client")
            .responds_like_instance_of(Utilities::GitHubClient)
          queued_jobs = {
            workflow_runs: [{
              id: "123",
            }],
          }
          github_client
            .expects(:repository_workflow_runs)
            .with(Constants::REPOSITORY, status: "queued")
            .returns(queued_jobs)
          github_client
            .expects(:cancel_workflow_run)
            .with(Constants::REPOSITORY, "123")

          # Then
          Services::GitHub::CancelWorkflows.call(github_client: github_client)
        end
      end
    end
  end
end
