defmodule TuistCloud.CommandEvents.Event do
  @moduledoc """
  A module that represents the projects table.
  """
  use Ecto.Schema
  import Ecto.Query, only: [from: 2]
  import Ecto.Changeset
  alias TuistCloud.Accounts.User
  alias TuistCloud.Projects.Project
  alias TuistCloud.Accounts.Account

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
    field :cacheable_targets, {:array, :string}
    field :local_cache_target_hits, {:array, :string}
    field :remote_cache_target_hits, {:array, :string}
    # Tests
    field :test_targets, {:array, :string}
    field :local_test_target_hits, {:array, :string}
    field :remote_test_target_hits, {:array, :string}

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

  defmacro this_month_fragment() do
    quote do
      fragment(
        "date_trunc('month', ?::timestamptz) = date_trunc('month', ?::timestamptz)",
        c.created_at,
        ^TuistCloud.Time.utc_now()
      )
    end
  end

  def current_month_remote_binary_cache_hits_query(%Project{id: project_id}) do
    from c in __MODULE__,
      where: c.project_id == ^project_id,
      where: this_month_fragment(),
      where: fragment("array_length(?, 1) > 0", c.remote_cache_target_hits)
  end

  def current_month_remote_binary_cache_hits_query(%Account{id: account_id}) do
    from c in __MODULE__,
      join: p in Project,
      on: p.id == c.project_id,
      where: p.account_id == ^account_id,
      where: this_month_fragment(),
      where: fragment("array_length(?, 1) > 0", c.remote_cache_target_hits)
  end

  def current_month_tested_target_hits_query(%Project{id: project_id}) do
    from c in __MODULE__,
      where: c.project_id == ^project_id,
      where:
        fragment(
          "date_trunc('month', ?::timestamptz) = date_trunc('month', ?::timestamptz)",
          c.created_at,
          ^TuistCloud.Time.utc_now()
        ),
      where: fragment("array_length(?, 1) > 0", c.remote_test_target_hits)
  end

  def current_month_tested_target_hits_query(%Account{id: account_id}) do
    from c in __MODULE__,
      join: p in Project,
      on: p.id == c.project_id,
      where: p.account_id == ^account_id,
      where:
        fragment(
          "date_trunc('month', ?::timestamptz) = date_trunc('month', ?::timestamptz)",
          c.created_at,
          ^TuistCloud.Time.utc_now()
        ),
      where: fragment("array_length(?, 1) > 0", c.remote_test_target_hits)
  end
end
