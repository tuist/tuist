defmodule Tuist.CommandEvents.Postgres.Event do
  @moduledoc """
  PostgreSQL schema for command events.
  """
  use Ecto.Schema

  import Ecto.Changeset
  import Ecto.Query

  alias Tuist.Accounts.User
  alias Tuist.AppBuilds.Preview
  alias Tuist.Projects.Project
  alias Tuist.Runs.Build

  @derive {
    Flop.Schema,
    filterable: [
      :id,
      :project_id,
      :name,
      :git_commit_sha,
      :git_ref,
      :git_branch,
      :status,
      :is_ci,
      :user_id,
      :hit_rate
    ],
    sortable: [:created_at, :ran_at, :duration, :hit_rate]
  }

  @primary_key {:id, :binary_id, autogenerate: true}
  schema "command_events" do
    field :legacy_id, :integer
    field :legacy_artifact_path, :boolean, default: false
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
    field :git_commit_sha, :string
    field :git_ref, :string
    field :git_branch, :string
    field :ran_at, :utc_datetime
    field :hit_rate, :float, virtual: true
    field :user_account_name, :string, virtual: true

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
    belongs_to :preview, Preview, type: UUIDv7
    belongs_to :project, Project
    belongs_to :user, User
    belongs_to :build_run, Build, type: UUIDv7

    # Rails names the field "created_at"
    # credo:disable-for-next-line Credo.Checks.TimestampsType
    timestamps(inserted_at: :created_at)
  end

  def command_with_name_query(name) do
    from c in __MODULE__,
      where: c.name == ^name
  end

  def create_changeset(event, attrs) do
    changeset =
      cast(event, attrs, [
        :legacy_artifact_path,
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
        :error_message,
        :preview_id,
        :git_commit_sha,
        :git_ref,
        :git_branch,
        :ran_at,
        :build_run_id
      ])

    is_ci = get_field(changeset, :is_ci)

    changeset
    |> validate_required(
      [:project_id, :name, :ran_at] ++
        if is_ci do
          []
        else
          [:user_id]
        end
    )
    |> put_change(
      :remote_test_target_hits_count,
      changeset |> get_field(:remote_test_target_hits) |> length()
    )
    |> put_change(
      :remote_cache_target_hits_count,
      changeset |> get_field(:remote_cache_target_hits) |> length()
    )
    |> validate_inclusion(:status, [:success, :failure])
  end

  def with_hit_rate(query) do
    from e in query,
      select_merge: %{
        hit_rate:
          fragment(
            "CASE WHEN array_length(?, 1) > 0 THEN (COALESCE(array_length(?, 1), 0) + COALESCE(array_length(?, 1), 0))::float / array_length(?, 1) * 100 ELSE NULL END",
            e.cacheable_targets,
            e.local_cache_target_hits,
            e.remote_cache_target_hits,
            e.cacheable_targets
          )
      }
  end
end
