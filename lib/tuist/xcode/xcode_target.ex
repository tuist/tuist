defmodule Tuist.Xcode.XcodeTarget do
  @moduledoc """
  Xcode graph target
  """
  use Ecto.Schema

  import Ecto.Changeset

  @primary_key {:id, UUIDv7, autogenerate: true}
  schema "xcode_targets" do
    field :name, :string
    field :binary_cache_hash, :string
    field :binary_build_duration, :integer
    field :binary_cache_hit, Ecto.Enum, values: [miss: 0, local: 1, remote: 2]
    field :selective_testing_hash, :string
    field :selective_testing_hit, Ecto.Enum, values: [miss: 0, local: 1, remote: 2]

    belongs_to :xcode_project, Tuist.Xcode.XcodeProject, type: UUIDv7

    timestamps(type: :utc_datetime)
  end

  def create_changeset(token, attrs) do
    token
    |> cast(attrs, [
      :name,
      :binary_cache_hash,
      :binary_cache_hit,
      :binary_build_duration,
      :selective_testing_hash,
      :selective_testing_hit,
      :xcode_project_id
    ])
    |> validate_required([:xcode_project_id, :name])
    |> unique_constraint([:xcode_project_id, :name])
  end
end
