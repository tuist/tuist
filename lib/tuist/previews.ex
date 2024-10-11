defmodule Tuist.Previews do
  @moduledoc """
  A module to deal with Tuist Previews.
  """
  alias Tuist.Repo
  alias Tuist.Projects.Project
  alias Tuist.Previews.Preview

  def create_preview(%{
        project: %Project{} = project,
        type: type,
        display_name: display_name,
        bundle_identifier: bundle_identifier,
        version: version
      }) do
    %Preview{}
    |> Preview.create_changeset(%{
      project_id: project.id,
      type: type,
      display_name: display_name,
      bundle_identifier: bundle_identifier,
      version: version
    })
    |> Repo.insert!()
  end

  def get_preview_by_id(id) do
    Repo.get_by(Preview, id: id)
  end

  def get_storage_key(%{
        account_handle: account_handle,
        project_handle: project_handle,
        preview_id: preview_id
      }) do
    "#{account_handle}/#{project_handle}/previews/#{preview_id}.zip"
  end
end
