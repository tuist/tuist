defmodule TuistCloud.CommandEvents.Event do
  @moduledoc """
  A module that represents the projects table.
  """
  use Ecto.Schema
  import Ecto.Query, only: [from: 2]
  import Ecto.Changeset
  alias TuistCloud.Projects.Project

  schema "command_events" do
    field :name, :string
    field :duration, :integer
    field :subcommand, :string
    field :command_arguments, :string
    field :tuist_version, :string
    field :swift_version, :string
    field :macos_version, :string
    # Binaries
    field :cacheable_targets, {:array, :string}
    field :local_cache_target_hits, {:array, :string}
    field :remote_cache_target_hits, {:array, :string}
    # Tests
    field :tested_targets, {:array, :string}
    field :local_tested_target_hits, {:array, :string}
    field :remote_tested_target_hits, {:array, :string}

    field :is_ci, :boolean
    field :client_id, :string
    belongs_to :project, Project

    # Rails names the field "created_at"
    timestamps(inserted_at: :created_at)
  end

  def command_with_name_query(name) do
    from c in __MODULE__,
      where: c.name == ^name
  end

  def create_changeset(event, attrs) do
    event
    |> cast(attrs, [
      :project_id,
      :name,
      :subcommand,
      :command_arguments,
      :duration,
      :tuist_version,
      :swift_version,
      :macos_version,
      :cacheable_targets,
      :local_cache_target_hits,
      :remote_cache_target_hits,
      :is_ci,
      :client_id,
      :created_at
    ])
    |> validate_required([:project_id, :name])
  end
end
