defmodule Tuist.Jams.Approval do
  @moduledoc "An immutable Ship review; only its owner may approve this exact state."
  use Ecto.Schema

  @primary_key {:id, :binary_id, autogenerate: true}
  schema "jam_ship_approvals" do
    field :request_id, Ecto.UUID
    field :jam_id, :binary_id
    field :account_id, :integer
    field :repository, :string
    field :sandbox_id, :binary_id
    field :head_sha, :string
    field :base_sha, :string
    field :diff, :string
    field :target_branch, :string
    field :mode, Ecto.Enum, values: [:direct, :branch]
    field :approved_by_id, :integer
    field :approved_at, :utc_datetime
    field :status, Ecto.Enum, values: [:pending, :approved, :executing, :succeeded, :failed], default: :pending
    timestamps(type: :utc_datetime)
  end
end
