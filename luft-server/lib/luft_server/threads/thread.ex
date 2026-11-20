defmodule LuftServer.Threads.Thread do
  @moduledoc "A conversation using its owner's explicitly delegated subscription."
  use Ecto.Schema

  @primary_key {:id, :binary_id, autogenerate: true}
  schema "threads" do
    field :account_id, :integer
    # Nullable only for staged imports; execution must load a fresh upstream scope.
    field :account_handle, :string
    field :owner_id, :integer
    field :owner_session_id, :binary_id
    field :request_id, Ecto.UUID
    field :request_hash, :binary, redact: true
    field :title, :string
    field :goal, :string
    field :provider, :string
    field :model, :string
    field :repository, :string
    field :base_branch, :string
    field :branch, :string
    field :base_sha, :string
    field :sandbox_id, :binary_id
    field :runner_id, :binary_id
    field :workspace_ready, :boolean, default: false
    field :workspace_ready_id, :string, virtual: true
    field :ship_mode, Ecto.Enum, values: [:direct, :branch], default: :branch
    field :status, Ecto.Enum, values: [:active, :archived], default: :active
    field :snoozed_until, :utc_datetime
    field :snoozed_until_needed, :boolean, default: false
    field :agent_status, :string, default: "queued"
    field :revision, :integer, default: 0
    field :messages, {:array, :map}, virtual: true, default: []
    field :has_more, :boolean, virtual: true, default: false
    field :next_before, :integer, virtual: true
    field :participant_ids, {:array, :integer}, virtual: true, default: []
    field :people, :map, virtual: true, default: %{}
    timestamps(type: :utc_datetime)
  end
end
