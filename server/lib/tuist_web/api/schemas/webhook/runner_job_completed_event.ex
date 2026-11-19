defmodule TuistWeb.API.Schemas.Webhook.RunnerJobCompletedEvent do
  @moduledoc """
  Envelope schema for the `runner_job.completed` webhook event. Fires when a job created through the runners API completes, fails or is cancelled.
  """
  alias OpenApiSpex.Schema
  alias TuistWeb.API.Schemas.Webhook.RunnerJob

  require OpenApiSpex

  OpenApiSpex.schema(%{
    title: "WebhookRunnerJobCompletedEvent",
    description:
      "Fires once a job created through the runners API completes, fails or is cancelled. The `object` carries the final `conclusion`.",
    type: :object,
    required: [:id, :type, :created, :object],
    properties: %{
      id: %Schema{
        type: :string,
        format: :uuid,
        description: "UUID unique to this delivery. Use it to deduplicate when retries fire."
      },
      type: %Schema{
        type: :string,
        enum: ["runner_job.completed"],
        description: "Discriminator for the event type."
      },
      created: %Schema{
        type: :integer,
        format: :int64,
        description: "Unix timestamp (seconds) at which Tuist enqueued the delivery."
      },
      object: RunnerJob
    }
  })
end
