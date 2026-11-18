defmodule TuistWeb.API.Schemas.Webhook.RunnerJobStartedEvent do
  @moduledoc """
  Envelope schema for the `runner_job.started` webhook event. Fires when a runner starts a job created through the runners API.
  """
  alias OpenApiSpex.Schema
  alias TuistWeb.API.Schemas.Webhook.RunnerJob

  require OpenApiSpex

  OpenApiSpex.schema(%{
    title: "WebhookRunnerJobStartedEvent",
    description:
      "Fires when a runner starts a job created through the runners API. Deliveries are at least once: a job whose first machine failed before running it can be started again.",
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
        enum: ["runner_job.started"],
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
