defmodule Tuist.Projects.VCSConnection do
  @moduledoc """
  A module that represents VCS connections between Tuist projects and external repositories.
  """
  use Ecto.Schema

  import Ecto.Changeset

  alias Tuist.Accounts.User
  alias Tuist.Projects.Project
  alias Tuist.VCS.GitHubAppInstallation

  @primary_key {:id, UUIDv7, autogenerate: true}
  @foreign_key_type UUIDv7
  schema "vcs_connections" do
    field :provider, Ecto.Enum, values: [github: 0]
    field :repository_full_handle, :string

    belongs_to :project, Project, type: :integer
    belongs_to :created_by, User, foreign_key: :created_by_id, type: :integer
    belongs_to :github_app_installation, GitHubAppInstallation

    timestamps(type: :utc_datetime)
  end

  def changeset(vcs_connection \\ %__MODULE__{}, attrs) do
    vcs_connection
    |> cast(attrs, [
      :project_id,
      :provider,
      :repository_full_handle,
      :created_by_id,
      :github_app_installation_id
    ])
    |> validate_required([:project_id, :provider, :repository_full_handle, :github_app_installation_id])
    |> validate_format(:repository_full_handle, ~r/^[\w\-\.]+\/[\w\-\.]+$/)
    |> unique_constraint([:project_id])
    |> foreign_key_constraint(:project_id)
    |> foreign_key_constraint(:created_by_id)
    |> foreign_key_constraint(:github_app_installation_id)
  end
end
