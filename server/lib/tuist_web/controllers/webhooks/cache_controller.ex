defmodule TuistWeb.Webhooks.CacheController do
  use TuistWeb, :controller

  alias Tuist.Cache
  alias Tuist.Projects

  require Logger

  def handle(conn, %{"events" => events}) when is_list(events) do
    full_handles =
      events
      |> Enum.map(fn event ->
        "#{event["account_handle"]}/#{event["project_handle"]}"
      end)
      |> Enum.uniq()

    projects_map = Projects.projects_by_full_handles(full_handles)

    {cas_events, module_cache_events} =
      Enum.reduce(events, {[], []}, fn event, {cas_acc, module_acc} ->
        case cache_event_from_payload(event, projects_map) do
          {:cas, cas_event} ->
            {[cas_event | cas_acc], module_acc}

          {:module_cache_hit, module_event} ->
            {cas_acc, [module_event | module_acc]}

          :skip ->
            {cas_acc, module_acc}
        end
      end)

    cas_events
    |> Enum.reverse()
    |> Cache.create_cas_events()

    if module_cache_events != [] do
      module_cache_events
      |> Enum.reverse()
      |> Cache.create_module_cache_events()
    end

    conn
    |> put_status(:accepted)
    |> json(%{})
    |> halt()
  end

  def handle(conn, _params) do
    conn
    |> put_status(:bad_request)
    |> json(%{error: "Invalid payload"})
    |> halt()
  end

  defp cache_event_from_payload(
         %{
           "account_handle" => account_handle,
           "project_handle" => project_handle,
           "event_type" => "module_cache_hit",
           "run_id" => run_id,
           "source" => source
         },
         projects_map
       ) do
    full_handle = "#{account_handle}/#{project_handle}"

    case Map.get(projects_map, full_handle) do
      %{id: project_id} ->
        {:module_cache_hit,
         %{
           project_id: project_id,
           run_id: run_id,
           source: source
         }}

      nil ->
        Logger.warning("Project not found for module cache hit: #{full_handle}")
        :skip
    end
  end

  defp cache_event_from_payload(
         %{
           "account_handle" => account_handle,
           "project_handle" => project_handle,
           "action" => action,
           "size" => size,
           "cas_id" => cas_id
         },
         projects_map
       ) do
    full_handle = "#{account_handle}/#{project_handle}"

    case Map.get(projects_map, full_handle) do
      %{id: project_id} ->
        {:cas,
         %{
           action: action,
           size: size,
           cas_id: cas_id,
           project_id: project_id
         }}

      nil ->
        Logger.warning("Project not found for cache event: #{full_handle}")
        :skip
    end
  end

  defp cache_event_from_payload(event, _projects_map) do
    Logger.warning("Invalid cache event payload: #{inspect(event)}")
    :skip
  end
end
