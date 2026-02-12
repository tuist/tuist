defmodule Cache.BodyReader do
  @moduledoc """
  Handles reading request bodies from Plug connections.

  Small bodies are read into memory, large bodies are streamed to temporary files
  to avoid memory pressure.

  ## Timeout Strategy

  Uses progressive timeouts inspired by Apache's `mod_reqtimeout` MinRate:
  - Initial timeout is calculated based on Content-Length and minimum throughput
  - Each subsequent chunk read uses a fresh timeout based on chunk size
  - This allows slow-but-steady connections while timing out stalled transfers

  See `TuistCommon.BodyReader` for the timeout calculation logic.
  """

  @max_upload_bytes 25 * 1024 * 1024
  @default_opts [length: @max_upload_bytes, read_length: 262_144]

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
  Reads the request body and writes it directly to an IO device.

  Returns `{:ok, bytes_written, conn}` on success,
  or `{:error, reason, conn}` on failure.
  """
  def read_to_device(conn, device, opts \\ []) do
    merged_opts = Keyword.merge(read_opts(conn), opts)
    max_bytes = Keyword.get(opts, :max_bytes, @max_upload_bytes)
    writer = fn chunk -> IO.binwrite(device, chunk) end

    conn
    |> Plug.Conn.read_body(merged_opts)
    |> handle_device_result(conn, merged_opts, device, writer, max_bytes)
  rescue
    Bandit.TransportError ->
      {:error, :cancelled, conn}
  end

  defp handle_device_result({:ok, body, conn_after}, _conn, _opts, _device, writer, max_bytes) do
    bytes = byte_size(body)

    cond do
      bytes > max_bytes -> {:error, :too_large, conn_after}
      bytes == 0 -> {:ok, 0, conn_after}
      true -> write_device_body(writer, body, bytes, conn_after)
    end
  end

  defp handle_device_result({:more, chunk, conn_after}, _conn, opts, device, writer, max_bytes) do
    bytes_read = byte_size(chunk)

    if bytes_read > max_bytes do
      {:error, :too_large, conn_after}
    else
      with :ok <- writer.(chunk),
           {:ok, conn_final, total_bytes} <- read_loop(conn_after, opts, device, bytes_read, writer, max_bytes) do
        {:ok, total_bytes, conn_final}
      else
        {:error, reason} -> {:error, reason, conn_after}
        {:error, reason, conn_final} -> {:error, reason, conn_final}
      end
    end
  end

  defp handle_device_result({:error, reason}, conn, _opts, _device, _writer, _max_bytes) do
    normalize_error(reason, conn)
  end

  defp write_device_body(writer, body, bytes, conn_after) do
    case writer.(body) do
      :ok -> {:ok, bytes, conn_after}
      {:error, reason} -> {:error, reason, conn_after}
    end
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

  defp normalize_error(:too_large, conn), do: {:error, :too_large, conn}
  defp normalize_error(reason, conn) when reason in [:timeout, :econnaborted], do: {:error, :timeout, conn}
  defp normalize_error(reason, conn), do: {:error, reason, conn}

  defp read_chunks(conn, opts, _first_chunk, bytes_read, :discard, max_bytes) do
    read_loop(conn, opts, nil, bytes_read, fn _chunk -> :ok end, max_bytes)
  end

  defp read_chunks(conn, opts, first_chunk, bytes_read, :store, max_bytes) do
    tmp_path = tmp_path(opts)

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
    # Use progressive timeout for each chunk read (similar to Apache mod_reqtimeout MinRate)
    # This resets the timeout on each successful read, allowing slow-but-steady connections
    chunk_opts = Keyword.put(opts, :read_timeout, chunk_timeout(opts))

    conn
    |> Plug.Conn.read_body(chunk_opts)
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
        write_chunk(conn_after, opts, device, bytes_read, chunk, writer, max_bytes, false)

      {:more, chunk, conn_after} ->
        write_chunk(conn_after, opts, device, bytes_read, chunk, writer, max_bytes, true)

      {:error, reason} ->
        {:error, reason, conn}
    end
  end

  defp write_chunk(conn, opts, device, bytes_read, chunk, writer, max_bytes, recurse?) do
    bytes = bytes_read + byte_size(chunk)

    if bytes > max_bytes do
      {:error, :too_large, conn}
    else
      case writer.(chunk) do
        :ok ->
          if recurse? do
            read_loop(conn, opts, device, bytes, writer, max_bytes)
          else
            {:ok, conn, bytes}
          end

        {:error, reason} ->
          {:error, reason, conn}
      end
    end
  end

  defp tmp_path(opts) do
    base = Keyword.get(opts, :tmp_dir, System.tmp_dir!())
    unique = :erlang.unique_integer([:positive, :monotonic])
    Path.join(base, ".cache-upload-#{unique}")
  end

  defp read_opts(conn) do
    base_opts = Map.get(conn.private, :body_read_opts, @default_opts)
    TuistCommon.BodyReader.read_opts(conn, base_opts)
  end

  defp chunk_timeout(opts) do
    TuistCommon.BodyReader.chunk_timeout(opts)
  end
end
