defmodule Atlas.Agents.Sessions.Session do
  use Atlas.Schema

  import Ecto.Changeset

  alias Atlas.Accounts.Account
  alias Atlas.Agents.Sessions.Event

  @statuses ~w(running succeeded failed)

  schema "agent_sessions" do
    field :agent, :string
    field :prompt, :string
    field :status, :string, default: "running"
    field :started_at, :utc_datetime_usec
    field :finished_at, :utc_datetime_usec
    field :duration_ms, :integer
    field :result, :map
    field :error, :string

    belongs_to :account, Account
    has_many :events, Event, foreign_key: :agent_session_id, preload_order: [asc: :occurred_at]

    timestamps()
  end

  def create_changeset(attrs) do
    {account_id, attrs} = Map.pop(attrs, :account_id)

    %__MODULE__{account_id: account_id}
    |> cast(attrs, [:id, :agent, :prompt, :status, :started_at])
    |> validate_required([:id, :agent, :prompt, :started_at])
    |> validate_inclusion(:status, @statuses)
  end

  def finalize_changeset(session, attrs) do
    {account_id, attrs} = Map.pop(attrs, :account_id)

    session
    |> maybe_put_account_id(account_id)
    |> cast(attrs, [:status, :finished_at, :duration_ms, :result, :error])
    |> validate_required([:status, :finished_at])
    |> validate_inclusion(:status, @statuses)
  end

  defp maybe_put_account_id(session, nil), do: session
  defp maybe_put_account_id(session, account_id), do: %{session | account_id: account_id}
end
