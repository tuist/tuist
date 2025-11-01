defmodule CacheWeb.CASController do
  use CacheWeb, :controller

  alias Cache.Authentication
  alias Cache.Disk

  @max_upload_bytes 25 * 1024 * 1024
  @body_read_opts [length: @max_upload_bytes, read_length: 262_144, read_timeout: 60_000]

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

        if Disk.exists?(key) do
          Logger.info("Artifact already exists, skipping save")

          case drain_body(conn) do
            {:ok, conn_after} ->
              send_resp(conn_after, :no_content, "")

            {:error, conn_after} ->
              Logger.warning("Failed to drain request body for existing artifact")
              send_resp(conn_after, :no_content, "")
          end
        else
          Logger.info("Persisting artifact")

          case read_cas_body(conn) do
            {:ok, {:binary, body}, conn_after} ->
              case Disk.put(key, body) do
                :ok ->
                  Logger.info("Artifact persisted successfully")
                  send_resp(conn_after, :no_content, "")

                {:error, _reason} ->
                  Logger.error("Failed to persist artifact")

                  conn_after
                  |> put_status(:internal_server_error)
                  |> json(%{message: "Failed to persist artifact"})
              end

            {:ok, {:tempfile, tmp_path}, conn_after} ->
              case Disk.put_file(key, tmp_path) do
                :ok ->
                  Logger.info("Artifact persisted successfully")
                  send_resp(conn_after, :no_content, "")

                {:error, :exists} ->
                  Logger.info("Artifact already persisted by another process")
                  send_resp(conn_after, :no_content, "")

                {:error, _reason} ->
                  Logger.error("Failed to persist artifact")

                  conn_after
                  |> put_status(:internal_server_error)
                  |> json(%{message: "Failed to persist artifact"})
              end

            {:error, :too_large, conn_after} ->
              Logger.error("Request body exceeded #{@max_upload_bytes} bytes")

              conn_after
              |> put_status(:payload_too_large)
              |> json(%{message: "Request body exceeded allowed size"})

            {:error, :timeout, conn_after} ->
              Logger.error("Timed out while reading request body")

              conn_after
              |> put_status(:request_timeout)
              |> json(%{message: "Request body read timed out"})

            {:error, reason, conn_after} ->
              Logger.error("Failed to read request body: #{inspect(reason)}")

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

  defp read_cas_body(conn) do
    opts = body_read_opts(conn)

    case Plug.Conn.read_body(conn, opts) do
      {:ok, body, conn_after} ->
        {:ok, {:binary, body}, conn_after}

      {:more, chunk, conn_after} ->
        stream_to_tempfile(conn_after, chunk, opts, byte_size(chunk))

      {:error, :too_large} ->
        {:error, :too_large, conn}

      {:error, reason} when reason in [:timeout, :econnaborted] ->
        {:error, :timeout, conn}

      {:error, reason} ->
        {:error, reason, conn}
    end
  end

  defp stream_to_tempfile(conn, initial_chunk, opts, bytes_written) do
    tmp_path = tmp_path()

    case File.open(tmp_path, [:write, :binary]) do
      {:ok, device} ->
        with :ok <- IO.binwrite(device, initial_chunk),
             :ok <- ensure_within_limit(bytes_written),
             result <- stream_chunks(conn, device, opts, bytes_written),
             {:ok, conn_after, _total} <- result do
          File.close(device)
          {:ok, {:tempfile, tmp_path}, conn_after}
        else
          {:error, reason, conn_after} ->
            File.close(device)
            File.rm(tmp_path)
            {:error, reason, conn_after}

          {:error, reason} ->
            File.close(device)
            File.rm(tmp_path)
            {:error, reason, conn}
        end

      {:error, reason} ->
        {:error, reason, conn}
    end
  end

  defp stream_chunks(conn, device, opts, bytes_written) do
    case Plug.Conn.read_body(conn, opts) do
      {:ok, chunk, conn_after} ->
        bytes = bytes_written + byte_size(chunk)

        cond do
          chunk == "" ->
            {:ok, conn_after, bytes_written}

          bytes > @max_upload_bytes ->
            {:error, :too_large, conn_after}

          true ->
            case IO.binwrite(device, chunk) do
              :ok -> {:ok, conn_after, bytes}
              {:error, reason} -> {:error, reason, conn_after}
            end
        end

      {:more, chunk, conn_after} ->
        bytes = bytes_written + byte_size(chunk)

        cond do
          bytes > @max_upload_bytes ->
            {:error, :too_large, conn_after}

          true ->
            case IO.binwrite(device, chunk) do
              :ok -> stream_chunks(conn_after, device, opts, bytes)
              {:error, reason} -> {:error, reason, conn_after}
            end
        end

      {:error, reason} ->
        {:error, reason, conn}
    end
  end

  defp drain_body(conn) do
    opts = body_read_opts(conn)

    case Plug.Conn.read_body(conn, opts) do
      {:ok, _body, conn_after} ->
        {:ok, conn_after}

      {:more, _chunk, conn_after} ->
        drain_body(conn_after)

      {:error, _reason} ->
        {:error, conn}
    end
  end

  defp tmp_path do
    base = System.tmp_dir!()
    unique = :erlang.unique_integer([:positive, :monotonic])
    Path.join(base, "cache-upload-#{unique}")
  end

  defp ensure_within_limit(bytes) when bytes > @max_upload_bytes, do: {:error, :too_large}
  defp ensure_within_limit(_bytes), do: :ok

  defp body_read_opts(conn) do
    Map.get(conn.private, :cas_body_read_opts, @body_read_opts)
  end
end
