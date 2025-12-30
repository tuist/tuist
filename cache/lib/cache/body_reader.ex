defmodule Cache.BodyReader do
  @moduledoc """
  Handles reading request bodies from Plug connections.

  Small bodies are read into memory, large bodies are streamed to temporary files
  to avoid memory pressure.
  """

  @max_upload_bytes 25 * 1024 * 1024
  @default_opts [length: @max_upload_bytes, read_length: 262_144, read_timeout: 60_000]

  @doc """
  Reads the request body from the connection.

  Returns:
  - `{:ok, body, conn}` - For small bodies that fit in memory
  - `{:ok, {:file, tmp_path}, conn}` - For large bodies streamed to temp file
  - `{:error, reason, conn}` - For errors like :too_large, :timeout, etc.
  """

  def read(conn, opts \\ []) do
    merged_opts = Keyword.merge(read_opts(conn), opts)
    max_bytes = Keyword.get(opts, :max_bytes, @max_upload_bytes)

    conn
    |> Plug.Conn.read_body(merged_opts)
    |> handle_read_result(conn, merged_opts, :store, max_bytes)
  rescue
    Bandit.TransportError ->
      {:error, :cancelled, conn}
  end

  @doc """
  Drains the request body without storing it.
  Useful when the upload already exists and we need to consume the body.
  """

  def drain(conn) do
    opts = read_opts(conn)

    case conn |> Plug.Conn.read_body(opts) |> handle_read_result(conn, opts, :discard, @max_upload_bytes) do
      {:ok, _, conn_after} -> {:ok, conn_after}
      {:error, _reason, conn_after} -> {:error, conn_after}
    end
  end

  defp handle_read_result(result, conn, opts, mode, max_bytes) do
    case result do
      {:ok, body, conn_after} ->
        {:ok, body, conn_after}

      {:more, chunk, conn_after} ->
        read_chunks(conn_after, opts, chunk, byte_size(chunk), mode, max_bytes)

      {:error, :too_large} ->
        {:error, :too_large, conn}

      {:error, reason} when reason in [:timeout, :econnaborted] ->
        {:error, :timeout, conn}

      {:error, reason} ->
        {:error, reason, conn}
    end
  end

  defp read_chunks(conn, opts, _first_chunk, bytes_read, :discard, max_bytes) do
    read_loop(conn, opts, nil, bytes_read, fn _chunk -> :ok end, max_bytes)
  end

  defp read_chunks(conn, opts, first_chunk, bytes_read, :store, max_bytes) do
    tmp_path = tmp_path()

    case File.open(tmp_path, [:write, :binary]) do
      {:ok, device} ->
        writer = fn chunk -> IO.binwrite(device, chunk) end

        case writer.(first_chunk) do
          :ok ->
            case read_loop(conn, opts, device, bytes_read, writer, max_bytes) do
              {:ok, conn_after, _bytes} ->
                File.close(device)
                {:ok, {:file, tmp_path}, conn_after}

              {:error, reason, conn_after} ->
                File.close(device)
                File.rm(tmp_path)
                {:error, reason, conn_after}
            end

          {:error, reason} ->
            File.close(device)
            File.rm(tmp_path)
            {:error, reason, conn}
        end

      {:error, reason} ->
        {:error, reason, conn}
    end
  end

  defp read_loop(conn, opts, device, bytes_read, writer, max_bytes) do
    conn
    |> Plug.Conn.read_body(opts)
    |> handle_loop_result(conn, opts, device, bytes_read, writer, max_bytes)
  rescue
    Bandit.TransportError ->
      {:error, :cancelled, conn}
  end

  defp handle_loop_result(result, conn, opts, device, bytes_read, writer, max_bytes) do
    case result do
      {:ok, "", conn_after} ->
        {:ok, conn_after, bytes_read}

      {:ok, chunk, conn_after} ->
        bytes = bytes_read + byte_size(chunk)

        if bytes > max_bytes do
          {:error, :too_large, conn_after}
        else
          case writer.(chunk) do
            :ok -> {:ok, conn_after, bytes}
            {:error, reason} -> {:error, reason, conn_after}
          end
        end

      {:more, chunk, conn_after} ->
        bytes = bytes_read + byte_size(chunk)

        if bytes > max_bytes do
          {:error, :too_large, conn_after}
        else
          case writer.(chunk) do
            :ok -> read_loop(conn_after, opts, device, bytes, writer, max_bytes)
            {:error, reason} -> {:error, reason, conn_after}
          end
        end

      {:error, reason} ->
        {:error, reason, conn}
    end
  end

  defp tmp_path do
    base = System.tmp_dir!()
    unique = :erlang.unique_integer([:positive, :monotonic])
    Path.join(base, "cache-upload-#{unique}")
  end

  defp read_opts(conn) do
    Map.get(conn.private, :body_read_opts, @default_opts)
  end
end
