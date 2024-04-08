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
      field :tuist_version, :string
      field :cacheable_targets, :string
      field :local_cache_target_hits, :string
      field :remote_cache_target_hits, :string
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
      |> cast(attrs, [:project_id, :name, :duration, :tuist_version, :cacheable_targets, :local_cache_target_hits, :remote_cache_target_hits, :created_at])
      |> validate_required([:project_id, :name])
    end
end
