defmodule Tuist.Projects.Project do
  @moduledoc """
  A module that represents projects.
  """
  use Ecto.Schema

  import Ecto.Changeset

  alias Tuist.Accounts.Account
  alias Tuist.Accounts.User
  alias Tuist.AppBuilds.Preview
  alias Tuist.Projects.VCSConnection
  alias Tuist.Vault.Binary

  @derive {
    Flop.Schema,
    filterable: [:account_id, :name, :visibility], sortable: [:name, :created_at], default_limit: 20
  }

  schema "projects" do
    field :token, :string
    field :name, :string
    field :visibility, Ecto.Enum, values: [private: 0, public: 1], default: :private
    field :default_branch, :string, default: "main"
    field :last_interacted_at, :naive_datetime, virtual: true
    field :default_previews_visibility, Ecto.Enum, values: [private: 0, public: 1], default: :private
    field :slack_channel_id, :string
    field :slack_channel_name, :string
    field :slack_webhook_url, Binary
    field :report_frequency, Ecto.Enum, values: [never: 0, daily: 1], default: :never
    field :report_days_of_week, {:array, :integer}, default: []
    field :report_schedule_time, :utc_datetime
    field :report_timezone, :string
    # Stamped by ReportWorker on each successful send; bounds the next report
    # window independently of oban_jobs retention. Set internally, not via the
    # public changeset.
    field :last_reported_at, :utc_datetime
    field :build_system, Ecto.Enum, values: [xcode: 0, gradle: 1], default: :xcode

    field :bundle_size_approval_policy, Ecto.Enum,
      values: [everyone: 0, selected: 1],
      default: :everyone

    field :auto_quarantine_flaky_tests, :boolean, default: false
    field :flaky_test_alerts_enabled, :boolean, default: false
    field :flaky_test_alerts_slack_channel_id, :string
    field :flaky_test_alerts_slack_channel_name, :string
    field :flaky_test_alerts_slack_webhook_url, Binary
    field :auto_mark_flaky_tests, :boolean, default: true
    field :auto_mark_flaky_threshold, :integer, default: 1
    field :flaky_cooldown_days, :integer, default: 14

    field :stress_new_tests_repetition_curve, {:array, :map},
      default: [
        %{"max_duration_ms" => 5_000, "repetitions" => 10},
        %{"max_duration_ms" => 10_000, "repetitions" => 5},
        %{"max_duration_ms" => 30_000, "repetitions" => 3},
        %{"max_duration_ms" => 300_000, "repetitions" => 2}
      ]

    field :stress_new_tests_candidate_cap, :integer, default: 200
    field :stress_new_tests_wall_clock_ceiling_ms, :integer, default: 600_000
    field :stress_new_tests_bulk_change_ratio, :float, default: 0.3
    field :stress_new_tests_bulk_change_floor, :integer, default: 50

    belongs_to :account, Account

    has_many :previews, Preview
    has_one :vcs_connection, VCSConnection

    has_many :users_with_last_visited_projects, User,
      foreign_key: :last_visited_project_id,
      foreign_key: :last_visited_project_id,
      on_delete: :nilify_all

    # Rails names the field "created_at"
    # credo:disable-for-next-line Credo.Checks.TimestampsType
    timestamps(inserted_at: :created_at)
  end

  def create_changeset(project \\ %__MODULE__{}, attrs) do
    project
    |> cast(attrs, [
      :token,
      :account_id,
      :name,
      :created_at,
      :visibility,
      :default_previews_visibility,
      :build_system
    ])
    |> validate_inclusion(:visibility, [:private, :public])
    |> validate_required([:token, :account_id, :name])
    |> validate_name()
    |> validate_inclusion(:default_previews_visibility, [:private, :public])
    |> validate_inclusion(:build_system, [:xcode, :gradle])
  end

  def update_changeset(project, attrs) do
    project
    |> cast(attrs, [
      :name,
      :default_branch,
      :visibility,
      :default_previews_visibility,
      :slack_channel_id,
      :slack_channel_name,
      :slack_webhook_url,
      :report_frequency,
      :report_days_of_week,
      :report_schedule_time,
      :report_timezone,
      :auto_quarantine_flaky_tests,
      :flaky_test_alerts_enabled,
      :flaky_test_alerts_slack_channel_id,
      :flaky_test_alerts_slack_channel_name,
      :flaky_test_alerts_slack_webhook_url,
      :auto_mark_flaky_tests,
      :auto_mark_flaky_threshold,
      :flaky_cooldown_days,
      :stress_new_tests_repetition_curve,
      :stress_new_tests_candidate_cap,
      :stress_new_tests_wall_clock_ceiling_ms,
      :stress_new_tests_bulk_change_ratio,
      :stress_new_tests_bulk_change_floor,
      :build_system,
      :bundle_size_approval_policy
    ])
    |> validate_name()
    |> validate_length(:default_branch, max: 255)
    |> validate_number(:auto_mark_flaky_threshold, greater_than: 0)
    |> validate_number(:flaky_cooldown_days, greater_than: 0)
    |> validate_number(:stress_new_tests_candidate_cap, greater_than: 0)
    |> validate_number(:stress_new_tests_wall_clock_ceiling_ms, greater_than: 0)
    |> validate_number(:stress_new_tests_bulk_change_ratio, greater_than: 0, less_than_or_equal_to: 1)
    |> validate_number(:stress_new_tests_bulk_change_floor, greater_than_or_equal_to: 0)
    |> validate_inclusion(:visibility, [:private, :public])
    |> validate_inclusion(:default_previews_visibility, [:private, :public])
    |> validate_inclusion(:build_system, [:xcode, :gradle])
    |> validate_inclusion(:bundle_size_approval_policy, [:everyone, :selected])
  end

  def xcode_project?(%__MODULE__{build_system: :xcode}), do: true
  def xcode_project?(_), do: false

  def gradle_project?(%__MODULE__{build_system: :gradle}), do: true
  def gradle_project?(_), do: false

  defp validate_name(changeset) do
    changeset
    |> validate_format(:name, ~r/^[a-zA-Z0-9-_]+$/,
      message: "must contain only alphanumeric characters, hyphens, and underscores"
    )
    |> validate_length(:name, min: 1, max: 32)
    |> validate_change(:name, fn :name, name ->
      if String.contains?(name, ".") do
        [
          name:
            "Project name can't contain a dot. Please use a different name, such as #{String.replace(name, ".", "-")}."
        ]
      else
        []
      end
    end)
    |> update_change(:name, &String.downcase/1)
    |> validate_exclusion(:name, Application.get_env(:tuist, :blocked_handles))
    |> unique_constraint([:name, :account_id], name: "index_projects_on_name_and_account_id")
  end
end
