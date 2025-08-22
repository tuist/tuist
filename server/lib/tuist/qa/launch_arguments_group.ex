defmodule Tuist.QA.LaunchArgumentsGroup do
  @moduledoc """
  Schema for QA launch arguments groups.
  """
  use Ecto.Schema

  import Ecto.Changeset

  alias Tuist.Projects.Project

  @primary_key {:id, UUIDv7, autogenerate: true}
  @foreign_key_type :id

  schema "qa_launch_arguments_groups" do
    field :name, :string
    field :description, :string
    field :value, :string

    belongs_to :project, Project

    timestamps(type: :utc_datetime)
  end

  def create_changeset(launch_arguments_group, attrs) do
    launch_arguments_group
    |> cast(attrs, [:project_id, :name, :description, :value])
    |> validate_required([:project_id, :name, :value])
    |> validate_length(:name, min: 1, max: 100)
    |> validate_format(:name, ~r/^[a-zA-Z0-9-_]+$/,
      message: "must contain only alphanumeric characters, hyphens, and underscores"
    )
    |> foreign_key_constraint(:project_id)
    |> unique_constraint([:project_id, :name], name: :qa_launch_arguments_groups_project_id_name_index)
  end

  def update_changeset(launch_arguments_group, attrs) do
    launch_arguments_group
    |> cast(attrs, [:name, :description, :value])
    |> validate_required([:name, :value])
    |> validate_length(:name, min: 1, max: 100)
    |> validate_format(:name, ~r/^[a-zA-Z0-9-_]+$/,
      message: "must contain only alphanumeric characters, hyphens, and underscores"
    )
    |> unique_constraint([:project_id, :name], name: :qa_launch_arguments_groups_project_id_name_index)
  end
end
