defmodule Tuist.Runners.InteractiveSession do
  @moduledoc """
  Session-scoped interactive access grant for one running runner job.

  The row is control-plane state only: it stores authorization,
  lifecycle, and audit metadata. Transport credentials such as Tart's
  generated VNC password stay outside the browser-facing product model.
  """
  use Ecto.Schema

  import Ecto.Changeset

  alias Tuist.Accounts.Account
  alias Tuist.Accounts.User

  schema "runner_interactive_sessions" do
    field :workflow_job_id, :integer
    field :pod_name, :string
    field :fleet_name, :string
    field :kind, Ecto.Enum, values: [vnc: "vnc", shell: "shell"]
    field :state, Ecto.Enum, values: [requested: "requested", ready: "ready", active: "active", closed: "closed"]
    field :token_hash, :binary, redact: true
    field :token, :string, virtual: true, redact: true
    field :connected_at, :utc_datetime
    field :closed_at, :utc_datetime
    field :expires_at, :utc_datetime
    field :last_activity_at, :utc_datetime
    field :relay_host, :string
    field :relay_port, :integer
    field :relay_ready_at, :utc_datetime
    field :connection_id, :string
    field :close_reason, :string

    belongs_to :account, Account
    belongs_to :requested_by_user, User

    timestamps(type: :utc_datetime)
  end

  def changeset(session, attrs) do
    session
    |> cast(attrs, [
      :account_id,
      :workflow_job_id,
      :pod_name,
      :fleet_name,
      :kind,
      :state,
      :token_hash,
      :requested_by_user_id,
      :connected_at,
      :closed_at,
      :expires_at,
      :last_activity_at,
      :relay_host,
      :relay_port,
      :relay_ready_at,
      :connection_id,
      :close_reason
    ])
    |> validate_number(:relay_port, greater_than: 0, less_than: 65_536)
    |> validate_required([
      :account_id,
      :workflow_job_id,
      :pod_name,
      :fleet_name,
      :kind,
      :state,
      :token_hash,
      :expires_at
    ])
    |> unique_constraint(:token_hash)
    |> unique_constraint([:workflow_job_id, :kind], name: :runner_interactive_sessions_open_job_kind_index)
    |> foreign_key_constraint(:account_id)
    |> foreign_key_constraint(:requested_by_user_id)
  end
end
