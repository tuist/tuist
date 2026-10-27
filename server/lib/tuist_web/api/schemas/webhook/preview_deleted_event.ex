defmodule TuistWeb.API.Schemas.Webhook.PreviewDeletedEvent do
  @moduledoc """
  Envelope schema for the `preview.deleted` webhook event. Fires after
  a preview is removed from the account.
  """
  alias OpenApiSpex.Schema
  alias TuistWeb.API.Schemas.Webhook.Preview

  require OpenApiSpex

  OpenApiSpex.schema(%{
    title: "WebhookPreviewDeletedEvent",
    description:
      "Fires after a preview is removed from the account. The `object` is a snapshot of the preview as it existed immediately before deletion.",
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
        enum: ["preview.deleted"],
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
