defmodule Tuist.Jams.Jam do
  @moduledoc "An owner-private conversation with an optional repository workspace."
  use Ecto.Schema

  @primary_key {:id, :binary_id, autogenerate: true}
  schema "jams" do
    field :account_id, :integer
    field :owner_id, :integer
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
    field :workspace_ready, :boolean, default: false
    field :ship_mode, Ecto.Enum, values: [:direct, :branch], default: :branch
    field :status, Ecto.Enum, values: [:active, :archived], default: :active
    field :agent_status, :string, default: "queued"
    field :revision, :integer, default: 0
    field :messages, {:array, :map}, virtual: true, default: []
    field :has_more, :boolean, virtual: true, default: false
    field :next_before, :integer, virtual: true
    timestamps(type: :utc_datetime)
  end
end
