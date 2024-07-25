defmodule Tuist.CommandEvents.Event do
  @moduledoc """
  A module that represents the projects table.
  """
  use Ecto.Schema
  import Ecto.Query
  import Ecto.Changeset
  alias Tuist.Accounts.User
  alias Tuist.Projects.Project

  @derive {
    Flop.Schema,
    filterable: [:project_id, :name], sortable: [:created_at]
  }

  schema "command_events" do
    field :name, :string
    field :duration, :integer
    field :subcommand, :string
    field :command_arguments, :string
    field :tuist_version, :string
    field :swift_version, :string
    field :macos_version, :string
    field :is_ci, :boolean
    field :client_id, :string
    field :status, Ecto.Enum, values: [success: 0, failure: 1]
    field :error_message, :string

    # Binary Cache
    field :cacheable_targets, {:array, :string}, default: []
    field :local_cache_target_hits, {:array, :string}, default: []
    field :remote_cache_target_hits, {:array, :string}, default: []
    field :remote_cache_target_hits_count, :integer

    # Tests
    field :test_targets, {:array, :string}, default: []
    field :local_test_target_hits, {:array, :string}, default: []
    field :remote_test_target_hits, {:array, :string}, default: []
    field :remote_test_target_hits_count, :integer

    # Associations
    belongs_to :project, Project
    belongs_to :user, User

    # Rails names the field "created_at"
    timestamps(inserted_at: :created_at)
  end

  def command_with_name_query(name) do
    from c in __MODULE__,
      where: c.name == ^name
  end

  def create_changeset(event, attrs) do
    changeset =
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
        :remote_cache_target_hits_count,
        :test_targets,
        :local_test_target_hits,
        :remote_test_target_hits,
        :remote_test_target_hits_count,
        :is_ci,
        :user_id,
        :client_id,
        :created_at,
        :status,
        :error_message
      ])

    is_ci = get_field(changeset, :is_ci)

    changeset
    |> validate_required(
      [:project_id, :name] ++
        if is_ci do
          []
        else
          [:user_id]
        end
    )
    |> put_change(
      :remote_test_target_hits_count,
      get_field(changeset, :remote_test_target_hits) |> length()
    )
    |> put_change(
      :remote_cache_target_hits_count,
      get_field(changeset, :remote_cache_target_hits) |> length()
    )
    |> validate_inclusion(:status, [:success, :failure])
  end
end
