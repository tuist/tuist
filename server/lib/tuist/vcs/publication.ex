defmodule Tuist.VCS.Publication do
  @moduledoc "An account-scoped irrevocable authorization for exactly one Git ref publication attempt."
  use Ecto.Schema

  @primary_key {:id, :binary_id, autogenerate: true}
  schema "vcs_publications" do
    field :account_id, :integer
    field :user_id, :integer
    field :request_id, Ecto.UUID
    field :fingerprint, :binary
    field :repository, :string
    field :operation_id, Ecto.UUID
    field :target_branch, :string
    field :base_sha, :string
    field :head_sha, :string
    field :mode, Ecto.Enum, values: [:direct, :branch]
    field :status, :string
    timestamps(type: :utc_datetime)
  end
end
