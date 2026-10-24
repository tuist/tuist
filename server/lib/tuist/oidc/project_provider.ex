defmodule Tuist.OIDC.ProjectProvider do
  @moduledoc """
  The CI providers a project has exchanged OIDC tokens from, and when it last
  did. Used to warn when scope rules would withhold writes from a provider
  whose claims they can't match.
  """
  use Ecto.Schema

  alias Tuist.Projects.Project

  @primary_key {:id, UUIDv7, autogenerate: true}
  schema "oidc_project_providers" do
    field :provider, Ecto.Enum, values: [:github_actions, :circleci, :bitrise]
    field :last_exchanged_at, :utc_datetime

    belongs_to :project, Project

    timestamps(type: :utc_datetime)
  end
end
