defmodule TuistWeb.API.Schemas.Webhook.TestCaseUpdatedEvent do
  @moduledoc """
  Envelope schema for the `test_case.updated` webhook event. Fires
  whenever a test case's lifecycle attributes change — flakiness flag
  flipped, state transitioned, etc.
  """
  alias OpenApiSpex.Schema
  alias TuistWeb.API.Schemas.Webhook.TestCase

  require OpenApiSpex

  OpenApiSpex.schema(%{
    title: "WebhookTestCaseUpdatedEvent",
    description:
      "Fires when a test case's attributes change — flakiness flag flipped, state transitioned to `muted` or `skipped`, etc. The `events` array tells you exactly which transitions caused the write.",
    type: :object,
    required: [:id, :type, :created, :object, :events],
    properties: %{
      id: %Schema{
        type: :string,
        format: :uuid,
        description: "UUID unique to this delivery. Use it to deduplicate when retries fire."
      },
      type: %Schema{
        type: :string,
        enum: ["test_case.updated"],
        description: "Discriminator for the event type."
      },
      created: %Schema{
        type: :integer,
        format: :int64,
        description: "Unix timestamp (seconds) at which Tuist enqueued the delivery."
      },
      object: TestCase,
      events: %Schema{
        type: :array,
        items: %Schema{
          type: :string,
          enum: [
            "marked_flaky",
            "unmarked_flaky",
            "muted",
            "unmuted",
            "skipped",
            "unskipped"
          ]
        },
        description:
          "Canonical transitions that caused the write. Receivers can branch on this without diffing the snapshot."
      },
      actor_id: %Schema{
        type: :integer,
        nullable: true,
        description:
          "Identifier of the account that performed the change, when initiated by a user. `null` for system / automation writes."
      },
      alert_id: %Schema{
        type: :string,
        format: :uuid,
        nullable: true,
        description:
          "Identifier of the automation alert whose action produced the change, when triggered by an automation. `null` otherwise."
      }
    }
  })
end
