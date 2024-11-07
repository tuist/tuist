defmodule Tuist.CommandEvents.Event do
  @moduledoc """
  A module that represents the projects table.
  """
  use Ecto.Schema
  import Ecto.Query
  import Ecto.Changeset
  alias Tuist.Previews.Preview
  alias Tuist.Accounts.User
  alias Tuist.Projects.Project

  @derive {
    Flop.Schema,
    filterable: [
      :project_id,
      :name,
      :git_commit_sha,
      :git_branch,
      :preview_display_name,
      :preview_bundle_identifier,
      :preview_id
    ],
    sortable: [:created_at],
    adapter_opts: [
      join_fields: [
        preview_id: [
          binding: :preview,
          field: :id,
          ecto_type: :uuid
        ],
        preview_display_name: [
          binding: :preview,
          field: :display_name,
          ecto_type: :string
        ],
        preview_bundle_identifier: [
          binding: :preview,
          field: :bundle_identifier,
          ecto_type: :string
        ]
      ]
    ]
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
    field :git_commit_sha, :string
    field :git_ref, :string
    field :git_branch, :string

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
        :error_message,
        :preview_id,
        :git_commit_sha,
        :git_ref,
        :git_branch
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
