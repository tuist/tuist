defmodule LuftServer.Audit do
  @moduledoc """
  An append-only record of who changed where people's data goes: MCP servers
  added, authorized and removed, and AI subscriptions connected and
  disconnected. Each event names the acting person (`actor_sub`, their Tuist
  subject), the owner it changed (`user:<sub>` or `account:<id>`), the row it
  changed and non-secret details such as the server's URL. Callers record an
  event in the same transaction as the change, so neither exists without the
  other. Events are never updated or deleted, and never hold credentials.
  """
  use Ecto.Schema

  alias LuftServer.Repo

  @primary_key {:id, :binary_id, autogenerate: true}
  schema "audit_events" do
    field :actor_sub, :string
    field :action, :string
    field :owner, :string
    field :subject_id, :binary_id
    field :details, :map, default: %{}
    timestamps(type: :utc_datetime_usec, updated_at: false)
  end

  def record!(actor_sub, action, owner, subject_id, details)
      when is_binary(actor_sub) and is_binary(action) and is_binary(owner) do
    Repo.insert!(
      %__MODULE__{
        actor_sub: actor_sub,
        action: action,
        owner: owner,
        subject_id: subject_id,
        details: details
      },
      log: false
    )
  end
end
