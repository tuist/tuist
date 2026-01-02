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
  alias Tuist.QA.LaunchArgumentGroup

  @derive {
    Flop.Schema,
    filterable: [:account_id, :name], sortable: [:name, :created_at], default_limit: 20
  }

  schema "projects" do
    field :token, :string
    field :name, :string
    field :visibility, Ecto.Enum, values: [private: 0, public: 1], default: :private
    field :default_branch, :string, default: "main"
    field :last_interacted_at, :naive_datetime, virtual: true
    field :default_previews_visibility, Ecto.Enum, values: [private: 0, public: 1], default: :private
    field :qa_app_description, :string, default: ""
    field :qa_email, :string, default: ""
    field :qa_password, :string, default: ""

    field :slack_channel_id, :string
    field :slack_channel_name, :string
    field :slack_report_frequency, Ecto.Enum, values: [never: 0, daily: 1], default: :never
    field :slack_report_days_of_week, {:array, :integer}, default: []
    field :slack_report_schedule_time, :utc_datetime
    field :slack_report_timezone, :string

    belongs_to :account, Account

    has_many :previews, Preview
    has_one :vcs_connection, VCSConnection
    has_many :qa_launch_argument_groups, LaunchArgumentGroup

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
      :default_previews_visibility
    ])
    |> validate_inclusion(:visibility, [:private, :public])
    |> validate_required([:token, :account_id, :name])
    |> validate_name()
    |> validate_inclusion(:default_previews_visibility, [:private, :public])
  end

  def update_changeset(project, attrs) do
    project
    |> cast(attrs, [
      :name,
      :default_branch,
      :visibility,
      :default_previews_visibility,
      :qa_app_description,
      :qa_email,
      :qa_password,
      :slack_channel_id,
      :slack_channel_name,
      :slack_report_frequency,
      :slack_report_days_of_week,
      :slack_report_schedule_time,
      :slack_report_timezone
    ])
    |> validate_name()
    |> validate_inclusion(:visibility, [:private, :public])
    |> validate_inclusion(:default_previews_visibility, [:private, :public])
  end

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
