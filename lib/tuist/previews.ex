defmodule Tuist.Previews do
  @moduledoc """
  A module to deal with Tuist Previews.
  """
  alias Tuist.Repo
  alias Tuist.Projects.Project
  alias Tuist.Previews.Preview

  def create_preview(%{project: %Project{} = project, display_name: display_name}) do
    %Preview{}
    |> Preview.create_changeset(%{
      project_id: project.id,
      display_name: display_name
    })
    |> Repo.insert!()
  end

  def get_preview_by_id(id) do
    Repo.get_by(Preview, id: id)
  end
end
