defmodule Tuist.Projects.VCSConnection do
  @moduledoc """
  A module that represents VCS connections between Tuist projects and external repositories.
  """
  use Ecto.Schema

  import Ecto.Changeset

  alias Tuist.Accounts.User
  alias Tuist.Origin.Installation, as: OriginInstallation
  alias Tuist.Projects.Project
  alias Tuist.VCS.GitHubAppInstallation

  @primary_key {:id, UUIDv7, autogenerate: true}
  @foreign_key_type UUIDv7
  schema "vcs_connections" do
    field :provider, Ecto.Enum, values: [github: 0, origin: 1]
    field :repository_full_handle, :string

    belongs_to :project, Project, type: :integer
    belongs_to :created_by, User, foreign_key: :created_by_id, type: :integer
    belongs_to :github_app_installation, GitHubAppInstallation
    belongs_to :origin_app_installation, OriginInstallation

    timestamps(type: :utc_datetime)
  end

  def changeset(vcs_connection \\ %__MODULE__{}, attrs) do
    vcs_connection
    |> cast(attrs, [
      :project_id,
      :provider,
      :repository_full_handle,
      :created_by_id,
      :github_app_installation_id,
      :origin_app_installation_id
    ])
    |> validate_required([:project_id, :provider, :repository_full_handle])
    |> validate_installation()
    |> validate_format(:repository_full_handle, ~r/^[\w\-\.]+\/[\w\-\.]+$/)
    |> unique_constraint([:project_id])
    |> foreign_key_constraint(:project_id)
    |> foreign_key_constraint(:created_by_id)
    |> foreign_key_constraint(:github_app_installation_id)
    |> foreign_key_constraint(:origin_app_installation_id)
    |> check_constraint(:provider, name: :vcs_connections_provider_installation)
  end

  defp validate_installation(changeset) do
    case get_field(changeset, :provider) do
      :github ->
        changeset
        |> validate_required([:github_app_installation_id])
        |> validate_absent(:origin_app_installation_id)

      :origin ->
        changeset
        |> validate_required([:origin_app_installation_id])
        |> validate_absent(:github_app_installation_id)

      _ ->
        changeset
    end
  end

  defp validate_absent(changeset, field) do
    if get_field(changeset, field),
      do: add_error(changeset, field, "must be absent for this provider"),
      else: changeset
  end
end
