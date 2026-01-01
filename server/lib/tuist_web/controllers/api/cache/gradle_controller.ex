defmodule TuistWeb.API.Cache.GradleController do
  @moduledoc """
  Controller for Gradle build cache operations.

  Implements the Gradle HTTP build cache protocol:
  - GET /:hash - Download artifact (200 with body, or 404)
  - PUT /:hash - Upload artifact (2xx on success, 413 if too large)

  Authentication uses HTTP Basic Auth with account tokens (handled by the
  authentication pipeline which now supports Basic Auth).
  """
  use TuistWeb, :controller

  alias Tuist.Storage
  alias TuistWeb.Authentication
  alias TuistWeb.Plugs.LoaderPlug

  @max_artifact_size 100_000_000

  plug LoaderPlug
  plug TuistWeb.API.Authorization.AuthorizationPlug, :cache

  def load(%{assigns: %{selected_project: project, selected_account: account}} = conn, %{"hash" => hash}) do
    current_subject = Authentication.authenticated_subject(conn)
    key = gradle_key(account, project, hash)

    if Storage.object_exists?(key, current_subject) do
      stream = Storage.stream_object(key, current_subject)

      conn
      |> put_resp_content_type("application/octet-stream")
      |> send_chunked(200)
      |> stream_data(stream)
    else
      send_resp(conn, :not_found, "")
    end
  end

  def save(%{assigns: %{selected_project: project, selected_account: account}} = conn, %{"hash" => hash}) do
    current_subject = Authentication.authenticated_subject(conn)
    key = gradle_key(account, project, hash)

    case Plug.Conn.read_body(conn, length: @max_artifact_size) do
      {:ok, body, conn} ->
        if !Storage.object_exists?(key, current_subject) do
          Storage.put_object(key, body, current_subject)
        end

        send_resp(conn, :ok, "")

      {:more, _partial, conn} ->
        conn
        |> put_status(413)
        |> json(%{error: "Payload too large"})

      {:error, _reason} ->
        conn
        |> put_status(:bad_request)
        |> json(%{error: "Failed to read request body"})
    end
  end

  defp gradle_key(account, project, hash) do
    "#{account.name}/#{project.name}/gradle/#{hash}"
  end

  defp stream_data(conn, stream) do
    Enum.reduce_while(stream, conn, fn chunk, conn ->
      case chunk(conn, chunk) do
        {:ok, conn} -> {:cont, conn}
        {:error, :closed} -> {:halt, conn}
      end
    end)
  end
end
