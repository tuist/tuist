defmodule Tuist.Xcode.Postgres.XcodeProject do
  @moduledoc """
  Xcode graph project
  """
  use Ecto.Schema

  import Ecto.Changeset

  @primary_key {:id, UUIDv7, autogenerate: true}
  schema "xcode_projects" do
    field :name, :string
    field :path, :string

    belongs_to :xcode_graph, Tuist.Xcode.Postgres.XcodeGraph, type: UUIDv7

    has_many :xcode_targets, Tuist.Xcode.Postgres.XcodeTarget

    timestamps(type: :utc_datetime)
  end

  def create_changeset(token, attrs) do
    token
    |> cast(attrs, [
      :name,
      :path,
      :xcode_graph_id
    ])
    |> validate_required([:name, :path, :xcode_graph_id])
    |> unique_constraint([:xcode_graph_id, :name])
  end
end
