defmodule TuistWeb.API.Schemas.Webhook.TestCaseCreatedEvent do
  @moduledoc """
  Envelope schema for the `test_case.created` webhook event. Fires the
  first time Tuist observes a new test case in the account.
  """
  alias OpenApiSpex.Schema
  alias TuistWeb.API.Schemas.Webhook.TestCase

  require OpenApiSpex

  OpenApiSpex.schema(%{
    title: "WebhookTestCaseCreatedEvent",
    description:
      "Fires the first time Tuist observes a test case in the account. The `object` is a snapshot of that newly-seen test case.",
    type: :object,
    required: [:id, :type, :created, :object],
    properties: %{
      id: %Schema{
        type: :string,
        format: :uuid,
        description:
          "UUID unique to this delivery. Use it to deduplicate when retries fire — the same `id` is sent on every retry of the same event."
      },
      type: %Schema{
        type: :string,
        enum: ["test_case.created"],
        description: "Discriminator for the event type."
      },
      created: %Schema{
        type: :integer,
        format: :int64,
        description: "Unix timestamp (seconds) at which Tuist enqueued the delivery."
      },
      object: TestCase
    }
  })
end
