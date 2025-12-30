defmodule Tuist.CacheActionItems.CacheActionItem do
  @moduledoc """
  A module that represents a Tuist cache action item.
  """

  use Ecto.Schema

  import Ecto.Changeset

  alias Tuist.Projects.Project

  @primary_key {:id, UUIDv7, autogenerate: true}
  schema "cache_action_items" do
    belongs_to :project, Project
    field :hash, :string

    timestamps(type: :utc_datetime)
  end

  def create_changeset(token, attrs) do
    token
    |> cast(attrs, [:project_id, :hash])
    |> validate_required([:project_id, :hash])
    |> unique_constraint([:hash, :project_id])
  end
end
