defmodule Atlas.Engineering.Projects.ProjectDomain do
  @moduledoc false

  use Ecto.Schema

  alias Atlas.Engineering.Domains.Domain
  alias Atlas.Engineering.Projects.Project

  @primary_key false
  @foreign_key_type :binary_id

  schema "projects_domains" do
    belongs_to :project, Project, primary_key: true
    belongs_to :domain, Domain, primary_key: true

    timestamps(type: :utc_datetime)
  end
end
