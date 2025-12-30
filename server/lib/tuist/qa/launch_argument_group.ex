defmodule Tuist.QA.LaunchArgumentGroup do
  @moduledoc """
  Schema for QA launch argument groups.
  """
  use Ecto.Schema

  import Ecto.Changeset

  alias Tuist.Projects.Project

  @primary_key {:id, UUIDv7, autogenerate: true}
  @foreign_key_type :id

  schema "qa_launch_argument_groups" do
    field :name, :string
    field :description, :string
    field :value, :string

    belongs_to :project, Project

    timestamps(type: :utc_datetime)
  end

  def create_changeset(launch_argument_group, attrs) do
    launch_argument_group
    |> cast(attrs, [:project_id, :name, :description, :value])
    |> validate_required([:project_id, :name, :value])
    |> validate_name()
    |> foreign_key_constraint(:project_id)
  end

  def update_changeset(launch_argument_group, attrs) do
    launch_argument_group
    |> cast(attrs, [:name, :description, :value])
    |> validate_required([:name, :value])
    |> validate_name()
  end

  defp validate_name(changeset) do
    changeset
    |> validate_length(:name, min: 1, max: 100)
    |> validate_format(:name, ~r/^[a-zA-Z0-9-_]+$/,
      message: "must contain only alphanumeric characters, hyphens, and underscores"
    )
    |> unique_constraint([:project_id, :name])
  end
end
