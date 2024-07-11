defmodule TuistCloud.Projects.Project do
  @moduledoc """
  A module that represents the projects table.
  """
  use Ecto.Schema
  alias TuistCloud.Accounts.Account
  alias TuistCloud.Accounts.User
  import Ecto.Changeset

  schema "projects" do
    field :token, :string
    field :name, :string
    field :visibility, Ecto.Enum, values: [private: 0, public: 1], default: :private
    belongs_to :account, Account

    has_many :users_with_last_visited_projects, User,
      foreign_key: :last_visited_project_id,
      foreign_key: :last_visited_project_id,
      on_delete: :nilify_all

    # Rails names the field "created_at"
    timestamps(inserted_at: :created_at)
  end

  def create_changeset(project, attrs) do
    project
    |> cast(attrs, [:token, :account_id, :name, :created_at, :visibility])
    |> validate_allowed_handle()
    |> validate_inclusion(:visibility, [:private, :public])
    |> validate_required([:token, :account_id, :name])
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
  end

  def validate_allowed_handle(changeset) do
    changeset |> validate_exclusion(:name, Application.get_env(:tuist_cloud, :blocked_handles))
  end
end
