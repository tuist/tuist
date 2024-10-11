defmodule Tuist.Previews.Preview do
  @moduledoc """
  A module that represents a preview.
  """
  alias Tuist.Projects.Project

  use Ecto.Schema
  import Ecto.Changeset

  @primary_key {:id, UUIDv7, autogenerate: true}
  schema "previews" do
    belongs_to :project, Project
    field :type, Ecto.Enum, values: [app_bundle: 0, ipa: 1]
    field :display_name, :string
    field :bundle_identifier, :string
    field :version, :string

    timestamps(type: :utc_datetime)
  end

  def create_changeset(token, attrs) do
    token
    |> cast(attrs, [:project_id, :type, :display_name, :bundle_identifier, :version])
    |> validate_required([:project_id, :type])
  end
end
