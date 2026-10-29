defmodule Atlas.Inbox.InboxEmail do
  @moduledoc """
  Persisted record of a raw RFC 822 message delivered by the Cloudflare email
  worker. The controller writes the row inside the request, then an Oban worker
  picks it up and runs DKIM authorization, the LLM agent, and attachment storage
  with retries.
  """

  use Atlas.Schema

  import Ecto.Changeset

  @statuses ~w(pending processed ignored failed)

  schema "inbox_emails" do
    field :raw_email, :binary
    field :envelope_from, :string
    field :envelope_to, :string
    field :received_at, :utc_datetime
    field :status, :string, default: "pending"
    field :processed_at, :utc_datetime
    field :outcome, :map
    field :last_error, :string

    timestamps()
  end

  def create_changeset(attrs) do
    %__MODULE__{}
    |> cast(attrs, [:raw_email, :envelope_from, :envelope_to, :received_at])
    |> validate_required([:raw_email, :received_at])
  end

  def status_changeset(inbox_email, attrs) do
    inbox_email
    |> cast(attrs, [:status, :processed_at, :outcome, :last_error])
    |> validate_inclusion(:status, @statuses)
  end
end
