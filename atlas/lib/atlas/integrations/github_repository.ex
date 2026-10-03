defmodule Atlas.Integrations.GitHubRepository do
  use Atlas.Schema

  import Ecto.Changeset

  alias Atlas.Integrations.GitHubApp

  schema "github_repositories" do
    field :owner, :string
    field :repo, :string

    belongs_to :github_app, GitHubApp

    timestamps()
  end

  def changeset(repository, attrs) do
    repository
    |> cast(attrs, [:owner, :repo, :github_app_id])
    |> validate_required([:owner, :repo, :github_app_id])
    |> unique_constraint([:owner, :repo, :github_app_id])
  end
end
