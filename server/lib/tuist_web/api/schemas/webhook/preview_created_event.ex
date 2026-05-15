defmodule TuistWeb.API.Schemas.Webhook.PreviewCreatedEvent do
  @moduledoc """
  Envelope schema for the `preview.created` webhook event. Fires once
  the app build for a new preview has finished uploading.
  """
  alias OpenApiSpex.Schema
  alias TuistWeb.API.Schemas.Webhook.Preview

  require OpenApiSpex

  OpenApiSpex.schema(%{
    title: "WebhookPreviewCreatedEvent",
    description:
      "Fires when a new preview is created in the account (once the app build has finished uploading). The `object` is a snapshot of the newly-created preview.",
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
        enum: ["preview.created"],
        description: "Discriminator for the event type."
      },
      created: %Schema{
        type: :integer,
        format: :int64,
        description: "Unix timestamp (seconds) at which Tuist enqueued the delivery."
      },
      object: Preview
    }
  })
end
