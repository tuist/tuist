defmodule Tuist.CacheActionItems do
  @moduledoc """
  A module that provides functions to interact with cache action items.
  """
  alias Tuist.Repo
  alias Tuist.Projects.Project
  alias Tuist.CacheActionItems.CacheActionItem
  import Ecto.Query

  def create_cache_action_item(%{
        hash: hash,
        project: %Project{id: project_id}
      }) do
    changeset =
      CacheActionItem.create_changeset(%CacheActionItem{}, %{
        hash: hash,
        project_id: project_id
      })

    Repo.insert!(changeset, on_conflict: :nothing, conflict_target: [:project_id, :hash])
  end

  def get_cache_action_item(%{project: %Project{id: project_id}, hash: hash}) do
    CacheActionItem |> Repo.get_by(project_id: project_id, hash: hash)
  end

  def delete_all_action_items(%{project: %Project{id: project_id}}) do
    from(c in CacheActionItem, where: c.project_id == ^project_id) |> Repo.delete_all()
  end
end
