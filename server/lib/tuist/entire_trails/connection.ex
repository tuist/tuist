defmodule Tuist.EntireTrails.Connection do
  @moduledoc false
  use Ecto.Schema

  import Ecto.Changeset

  @primary_key {:id, UUIDv7, autogenerate: true}
  @foreign_key_type UUIDv7
  schema "entire_trail_connections" do
    belongs_to :project, Tuist.Projects.Project, type: :integer
    belongs_to :installation, Tuist.Entire.Installation
    field :repository_id, :string
    field :repository_name, :string
    timestamps(type: :utc_datetime)
  end

  def changeset(connection, attrs) do
    connection
    |> cast(attrs, [:project_id, :installation_id, :repository_id, :repository_name])
    |> validate_required([:project_id, :installation_id, :repository_id, :repository_name])
    |> unique_constraint(:project_id)
    |> foreign_key_constraint(:project_id)
    |> foreign_key_constraint(:installation_id)
  end
end
