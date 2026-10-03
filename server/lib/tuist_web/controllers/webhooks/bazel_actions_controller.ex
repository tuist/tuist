defmodule TuistWeb.Webhooks.BazelActionsController do
  use TuistWeb, :controller

  alias Tuist.Bazel.Action
  alias Tuist.Projects
  alias TuistWeb.Plugs.RequireCacheEndpointPlug

  def handle(conn, params) do
    conn = RequireCacheEndpointPlug.call(conn, [])

    if conn.halted do
      conn
    else
      with %{"account_handle" => account, "project_handle" => name} <- params,
           true <- valid_handle?(account) and valid_handle?(name),
           %{build_system: :bazel} = project <-
             Projects.projects_by_full_handles(["#{account}/#{name}"])["#{account}/#{name}"],
           :ok <- Action.ingest(project, params) do
        conn |> put_status(:accepted) |> json(%{}) |> halt()
      else
        _ -> conn |> put_status(:bad_request) |> json(%{error: "Invalid Bazel action"}) |> halt()
      end
    end
  end

  defp valid_handle?(value), do: is_binary(value) and byte_size(value) in 1..255
end
