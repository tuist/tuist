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

  alias Tuist.Accounts.AuthenticatedAccount
  alias Tuist.Projects
  alias Tuist.Storage
  alias TuistWeb.Authentication

  @max_artifact_size 100_000_000

  plug :validate_cache_scope
  plug :load_project

  def load(conn, %{"hash" => hash}) do
    account = conn.assigns.account
    project = conn.assigns.project
    authenticated_account = conn.assigns.authenticated_account
    key = gradle_key(account, project, hash)

    if Storage.object_exists?(key, authenticated_account) do
      stream = Storage.stream_object(key, authenticated_account)

      conn
      |> put_resp_content_type("application/octet-stream")
      |> send_chunked(200)
      |> stream_data(stream)
    else
      send_resp(conn, :not_found, "")
    end
  end

  def save(conn, %{"hash" => hash}) do
    account = conn.assigns.account
    project = conn.assigns.project
    authenticated_account = conn.assigns.authenticated_account
    key = gradle_key(account, project, hash)

    case Plug.Conn.read_body(conn, length: @max_artifact_size) do
      {:ok, body, conn} ->
        unless Storage.object_exists?(key, authenticated_account) do
          Storage.put_object(key, body, authenticated_account)
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

  defp validate_cache_scope(conn, _opts) do
    case Authentication.authenticated_subject(conn) do
      %AuthenticatedAccount{scopes: scopes} = authenticated_account ->
        if has_cache_scope?(scopes) do
          assign(conn, :authenticated_account, authenticated_account)
        else
          conn
          |> put_status(:forbidden)
          |> json(%{error: "Token does not have cache access"})
          |> halt()
        end

      _ ->
        conn
        |> put_status(:forbidden)
        |> json(%{error: "Account token required for Gradle cache access"})
        |> halt()
    end
  end

  defp has_cache_scope?(scopes) do
    Enum.any?(scopes, fn scope ->
      scope in ["project:cache:read", "project:cache:write"]
    end)
  end

  defp load_project(conn, _opts) do
    account_handle = conn.params["account_handle"]
    project_handle = conn.params["project_handle"]
    authenticated_account = conn.assigns.authenticated_account

    with {:ok, project} <- Projects.get_project_by_slug("#{account_handle}/#{project_handle}") do
      if can_access_project?(authenticated_account, project) do
        conn
        |> assign(:account, authenticated_account.account)
        |> assign(:project, project)
      else
        conn
        |> put_status(:forbidden)
        |> json(%{error: "Token does not have access to this project"})
        |> halt()
      end
    else
      {:error, _} ->
        conn
        |> put_status(:not_found)
        |> json(%{error: "Project not found"})
        |> halt()
    end
  end

  defp can_access_project?(authenticated_account, project) do
    cond do
      authenticated_account.all_projects ->
        authenticated_account.account.id == project.account_id

      true ->
        project.id in authenticated_account.project_ids and
          authenticated_account.account.id == project.account_id
    end
  end
end
