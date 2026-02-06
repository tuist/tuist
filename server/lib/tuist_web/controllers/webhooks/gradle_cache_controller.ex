defmodule TuistWeb.Webhooks.GradleCacheController do
  use TuistWeb, :controller

  alias Tuist.Gradle
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

    cache_events =
      events
      |> Enum.map(fn event ->
        %{
          "account_handle" => account_handle,
          "project_handle" => project_handle,
          "action" => action,
          "size" => size,
          "cache_key" => cache_key
        } = event

        full_handle = "#{account_handle}/#{project_handle}"

        case Map.get(projects_map, full_handle) do
          %{id: project_id} ->
            %{
              action: action,
              size: size,
              cache_key: cache_key,
              project_id: project_id,
              account_handle: account_handle,
              project_handle: project_handle
            }

          nil ->
            Logger.warning("Project not found for Gradle cache event: #{full_handle}")

            nil
        end
      end)
      |> Enum.reject(&is_nil/1)

    Gradle.create_cache_events(cache_events)

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
end
