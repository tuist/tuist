defmodule Tuist.Projects.Preview do
  @moduledoc """
  A module that represents a preview.
  """
  alias Tuist.Projects.Project

  use Ecto.Schema
  import Ecto.Changeset

  @primary_key {:id, UUIDv7, autogenerate: true}
  schema "previews" do
    belongs_to :project, Project

    timestamps(type: :utc_datetime)
  end

  def create_changeset(token, attrs) do
    token
    |> cast(attrs, [:project_id])
    |> validate_required([:project_id])
  end
end
