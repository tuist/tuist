defmodule TuistWeb.API.Schemas.Webhook.RunnerJob do
  @moduledoc """
  The `object` payload shared by every `runner_job.*` webhook event.

  Mirrors `Tuist.Runners.APIJobs.webhook_object/2`; keep both in sync when
  adding fields.
  """
  alias OpenApiSpex.Schema

  require OpenApiSpex

  OpenApiSpex.schema(%{
    title: "WebhookRunnerJob",
    description: "Snapshot of the runner job, created through the runners API, that triggered the webhook event.",
    type: :object,
    required: [:workflow_job_id, :name, :repository, :commit_sha, :profile, :platform, :status, :enqueued_at],
    properties: %{
      workflow_job_id: %Schema{type: :integer, description: "The job's identifier, as the create response returned it."},
      idempotency_key: %Schema{
        type: :string,
        nullable: true,
        description: "The idempotency key the job was created with, when it had one."
      },
      name: %Schema{type: :string, description: "The job name."},
      repository: %Schema{type: :string, description: "The repository name shown for the job."},
      ref: %Schema{type: :string, nullable: true, description: "The ref the job was created for, when given."},
      commit_sha: %Schema{type: :string, description: "The commit the job checked out."},
      profile: %Schema{type: :string, description: "The runs-on label of the profile the job ran on."},
      platform: %Schema{type: :string, description: "The profile's platform, such as linux or macos."},
      status: %Schema{
        type: :string,
        description: "The job's lifecycle status, such as queued, claimed, running, completed or cancelled."
      },
      conclusion: %Schema{
        type: :string,
        nullable: true,
        description: "On completion, success, failure or cancelled."
      },
      enqueued_at: %Schema{type: :string, format: :"date-time"},
      started_at: %Schema{type: :string, format: :"date-time", nullable: true},
      completed_at: %Schema{type: :string, format: :"date-time", nullable: true}
    }
  })
end
