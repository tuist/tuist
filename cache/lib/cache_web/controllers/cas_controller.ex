defmodule CacheWeb.CASController do
  use CacheWeb, :controller

  alias Cache.Authentication
  alias Cache.Disk

  require Logger

  def authorize(conn, %{"account_handle" => account, "project_handle" => project}) 
      when is_binary(account) and account != "" and is_binary(project) and project != "" do
    case Authentication.ensure_project_accessible(conn, account, project) do
      {:ok, _} -> send_resp(conn, :no_content, "")
      {:error, status, _} -> send_resp(conn, status, "")
    end
  end

  def authorize(conn, _params), do: send_resp(conn, 400, "")

  defp cas_key(account_handle, project_handle, id) do
    "#{account_handle}/#{project_handle}/cas/#{id}"
  end

  def save(conn, %{"id" => id, "account_handle" => account_handle, "project_handle" => project_handle}) do
    case Authentication.ensure_project_accessible(conn, account_handle, project_handle) do
      {:ok, _auth_header} ->
        Logger.info("Found project: #{account_handle}/#{project_handle}")

        key = cas_key(account_handle, project_handle, id)
        Logger.info("Cache key: #{key}")

        raw_body = Map.get(conn.private, :raw_body)

        if Disk.exists?(key) do
          Logger.info("Artifact already exists, skipping save")
          cleanup_tempfile(raw_body)
          send_resp(conn, :no_content, "")
        else
          Logger.info("Persisting artifact")

          case persist_body(key, raw_body, conn) do
            {:ok, conn_after} ->
              Logger.info("Artifact persisted successfully")
              send_resp(conn_after, :no_content, "")

            {:error, conn_after} ->
              Logger.error("Failed to persist artifact")

              conn_after
              |> put_status(:internal_server_error)
              |> json(%{message: "Failed to persist artifact"})
          end
        end

      {:error, status, message} ->
        conn
        |> put_status(status)
        |> json(%{message: message})
    end
  end

  defp persist_body(key, {:tempfile, tmp_path}, conn) do
    case Disk.put_file(key, tmp_path) do
      :ok -> {:ok, conn}
      {:error, :exists} -> {:ok, conn}
      {:error, _reason} -> {:error, conn}
    end
  end

  defp persist_body(key, _raw_body, conn) do
    case Plug.Conn.read_body(conn, length: 100_000_000) do
      {:ok, body, conn_after} ->
        case Disk.put(key, body) do
          :ok -> {:ok, conn_after}
          {:error, _reason} -> {:error, conn_after}
        end

      {:error, _reason} ->
        {:error, conn}
    end
  end

  defp cleanup_tempfile({:tempfile, tmp_path}) do
    File.rm(tmp_path)
    :ok
  end

  defp cleanup_tempfile(_), do: :ok

  # No URI fallback; nginx passes explicit project context via query params
end
