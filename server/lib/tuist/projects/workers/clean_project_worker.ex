defmodule Tuist.Projects.Workers.CleanProjectWorker do
  @moduledoc false
  # We need to make sure that when there's a cleaning already happening for a given project
  # we don't schedule another one. Otherwise we might end up with a race condition.
  use Oban.Worker, unique: [keys: [:project_id], states: [:scheduled]]

  alias Tuist.Cache
  alias Tuist.CacheActionItems
  alias Tuist.Storage

  @impl Oban.Worker
  def perform(%Oban.Job{args: %{"project_id" => project_id}} = _job) do
    project = Tuist.Projects.get_project_by_id(project_id)

    if is_nil(project) do
      :ok
    else
      project_slug = "#{project.account.name}/#{project.name}"

      Task.await_many([
        Task.async(fn -> Storage.delete_all_objects("#{project_slug}/cas", project.account) end),
        Task.async(fn -> Storage.delete_all_objects("#{project_slug}/builds", project.account) end),
        Task.async(fn -> Storage.delete_all_objects("#{project_slug}/tests", project.account) end),
        Task.async(fn -> CacheActionItems.delete_all_action_items(%{project: project}) end),
        Task.async(fn -> Cache.delete_entries_by_project_id(project.id) end)
      ])

      :ok
    end
  end
end
