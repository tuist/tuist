defmodule Tuist.CommandEvents.Event do
  @moduledoc """
  A module that represents the projects table.
  """
  use Ecto.Schema
  import Ecto.Query
  import Ecto.Changeset
  alias Tuist.Accounts.User
  alias Tuist.Projects.Project
  alias Tuist.Accounts.Account

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
    # Binaries
    field :cacheable_targets, {:array, :string}, default: []
    field :local_cache_target_hits, {:array, :string}, default: []
    field :remote_cache_target_hits, {:array, :string}, default: []

    # Tests
    field :test_targets, {:array, :string}, default: []
    field :local_test_target_hits, {:array, :string}, default: []
    field :remote_test_target_hits, {:array, :string}, default: []

    field :is_ci, :boolean
    field :client_id, :string
    field :status, Ecto.Enum, values: [success: 0, failure: 1]
    field :error_message, :string
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
        :test_targets,
        :local_test_target_hits,
        :remote_test_target_hits,
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
    |> validate_inclusion(:status, [:success, :failure])
  end

  def get_current_month_remote_cache_hits_count_query(%Account{id: account_id}) do
    today = Tuist.Time.utc_now()
    beginning_of_month = Timex.beginning_of_month(today)

    from c in __MODULE__,
      join: p in Project,
      on: p.id == c.project_id and p.account_id == ^account_id,
      where:
        c.created_at >= ^beginning_of_month and
          c.created_at < ^today,
      select:
        count(
          fragment(
            "CASE WHEN COALESCE(? <> '{}', false) OR COALESCE(? <> '{}', false) THEN 1 END",
            c.remote_cache_target_hits,
            c.remote_test_target_hits
          )
        )
  end
end
