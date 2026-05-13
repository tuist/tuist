defmodule Tuist.Webhooks.DeliveryAttempt do
  @moduledoc """
  One HTTP attempt at delivering a webhook event to an endpoint.

  An event delivered via the `DeliveryWorker` produces one row per HTTP
  call — the initial send and each retry — capturing what we sent and
  what came back so the dashboard can show the request body, response
  headers, and error inline.

  The `status` field collapses each row to either `"delivered"` (2xx) or
  `"failed"` (non-2xx or transport error). Higher-level lifecycle states
  like "pending" or "retrying" live on the Oban job, not on individual
  attempts.
  """
  use Ecto.Schema

  alias Tuist.Webhooks.WebhookEndpoint

  @primary_key {:id, UUIDv7, autogenerate: true}
  @foreign_key_type :binary_id
  schema "webhook_delivery_attempts" do
    field :event_id, :string
    field :event_type, :string
    field :attempt, :integer
    field :status, :string
    field :request_body, :string
    field :request_headers, :map
    field :response_status, :integer
    field :response_headers, :map
    field :response_body, :string
    field :error, :string
    field :duration_ms, :integer

    belongs_to :webhook_endpoint, WebhookEndpoint

    timestamps(type: :utc_datetime_usec)
  end
end
