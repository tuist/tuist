defmodule Tuist.CacheActionItems do
  @moduledoc """
  A module that provides functions to interact with cache action items.
  """
  import Ecto.Query

  alias Tuist.CacheActionItems.CacheActionItem
  alias Tuist.Projects.Project
  alias Tuist.Repo

  def create_cache_action_item(%{hash: hash, project: %Project{id: project_id}}) do
    changeset =
      CacheActionItem.create_changeset(%CacheActionItem{}, %{
        hash: hash,
        project_id: project_id
      })

    Repo.insert!(changeset, on_conflict: :nothing, conflict_target: [:project_id, :hash])
  end

  def create_cache_action_items(cache_action_items) do
    Repo.insert_all(CacheActionItem, cache_action_items,
      on_conflict: :nothing,
      conflict_target: [:project_id, :hash],
      timeout: to_timeout(second: 30)
    )
  end

  def get_cache_action_item(%{project: %Project{id: project_id}, hash: hash}) do
    Repo.get_by(CacheActionItem, project_id: project_id, hash: hash)
  end

  def delete_all_action_items(%{project: %Project{id: project_id}}) do
    Repo.delete_all(from(c in CacheActionItem, where: c.project_id == ^project_id))
  end
end
