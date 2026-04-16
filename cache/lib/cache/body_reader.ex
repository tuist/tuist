defmodule Cache.BodyReader do
  @moduledoc """
  Handles reading request bodies from Plug connections.

  Bodies that fit within the configured read chunk stay in memory, while larger
  bodies are streamed to temporary files or devices to avoid memory pressure.

  ## Timeout Strategy

  Uses progressive timeouts inspired by Apache's `mod_reqtimeout` MinRate:
  - Initial timeout is calculated based on Content-Length and minimum throughput
  - Each subsequent chunk read uses a fresh timeout based on chunk size
  - This allows slow-but-steady connections while timing out stalled transfers

  See `TuistCommon.BodyReader` for the timeout calculation logic.

  ## Content-Length enforcement

  When the request carries a valid `Content-Length` header, `read/2` and
  `read_to_device/3` verify that the number of bytes delivered to the
  caller matches the declared length. If fewer bytes arrive the reader
  returns `{:error, :truncated, conn}` and cleans up any temp file it
  had started, instead of pretending the body is complete.

  Why this matters: the underlying HTTP adapter occasionally reports
  `{:ok, partial, conn}` when a client closes the socket mid-upload
  (cleanly enough that the adapter doesn't raise but short of the
  declared Content-Length). Without this check a truncated upload can be
  persisted as a fully-valid cache object. Subsequent GETs then serve
  those partial bytes with a `200 OK` and a correct `Content-Length`
  header. The client has no HTTP-level signal that anything is wrong,
  but whatever format lives inside the bytes (gzip, zip, a classpath
  snapshot, etc.) is truncated, and parsers fail deep inside the build
  with exceptions that often carry no message. Enforcing the declared
  length at the boundary prevents that entire failure class.
  """

  alias CacheWeb.RequestTimeoutError

  @max_upload_bytes 25 * 1024 * 1024
  @default_read_length 262_144
  @default_opts [length: @default_read_length, read_length: @default_read_length]

  @doc """
  Reads the request body for `Plug.Parsers`.

  Raises `CacheWeb.RequestTimeoutError` for body read timeouts so Phoenix can
  render a `408` JSON response through the normal error pipeline.
  """
  def read_body(conn, opts) do
    case read_conn_body(conn, opts) do
      {:ok, {:ok, body, conn_after}} ->
        {:ok, body, conn_after}

      {:ok, {:more, body, conn_after}} ->
        {:more, body, conn_after}

      {:ok, {:error, reason}} when reason in [:timeout, :econnaborted] ->
        raise RequestTimeoutError, message: "Request body read timed out"

      {:ok, {:error, reason}} ->
        {:error, reason}

      {:exception, error, stacktrace} ->
        handle_parser_exception(error, stacktrace)
    end
  end

  defp handle_parser_exception(%Bandit.TransportError{error: reason}, _stacktrace)
       when reason in [:timeout, :econnaborted] do
    raise RequestTimeoutError, message: "Request body read timed out"
  end

  defp handle_parser_exception(error, stacktrace) do
    reraise error, stacktrace
  end

  @doc """
  Reads the request body from the connection.

  Returns:
  - `{:ok, body, conn}` - For small bodies that fit in memory
  - `{:ok, {:file, tmp_path}, conn}` - For large bodies streamed to temp file
  - `{:error, :truncated, conn}` - Fewer bytes arrived than Content-Length declared
  - `{:error, reason, conn}` - For errors like :too_large, :timeout, etc.

  See the module doc for the rationale behind the `:truncated` branch.
  """

  def read(conn, opts \\ []) do
    max_bytes = Keyword.get(opts, :max_bytes, @max_upload_bytes)
    merged_opts = merged_opts(conn, opts, max_bytes)
    expected_length = TuistCommon.BodyReader.get_content_length(conn)

    result =
      case read_conn_body(conn, plug_read_opts(merged_opts)) do
        {:ok, read_result} -> handle_read_result(read_result, conn, merged_opts, :store, max_bytes)
        {:exception, error, _stacktrace} -> normalize_read_exception(error, conn)
      end

    enforce_content_length(result, expected_length)
  end

  @doc """
  Reads the request body and writes it directly to an IO device.

  Returns `{:ok, bytes_written, conn}` on success,
  `{:error, :truncated, conn}` if the number of bytes written differs from
  the request's Content-Length,
  or `{:error, reason, conn}` on failure.
  """
  def read_to_device(conn, device, opts \\ []) do
    max_bytes = Keyword.get(opts, :max_bytes, @max_upload_bytes)
    merged_opts = merged_opts(conn, opts, max_bytes)
    expected_length = TuistCommon.BodyReader.get_content_length(conn)
    writer = fn chunk -> :file.write(device, chunk) end

    result =
      case read_conn_body(conn, plug_read_opts(merged_opts)) do
        {:ok, read_result} -> handle_device_result(read_result, conn, merged_opts, writer, max_bytes)
        {:exception, error, _stacktrace} -> normalize_read_exception(error, conn)
      end

    enforce_device_content_length(result, expected_length)
  end

  defp handle_device_result({:ok, body, conn_after}, _conn, _opts, writer, max_bytes) do
    bytes = byte_size(body)

    cond do
      bytes > max_bytes -> {:error, :too_large, conn_after}
      bytes == 0 -> {:ok, 0, conn_after}
      true -> write_device_body(writer, body, bytes, conn_after)
    end
  end

  defp handle_device_result({:more, chunk, conn_after}, _conn, opts, writer, max_bytes) do
    bytes_read = byte_size(chunk)

    if bytes_read > max_bytes do
      {:error, :too_large, conn_after}
    else
      with :ok <- writer.(chunk),
           {:ok, conn_final, total_bytes} <- read_loop(conn_after, opts, bytes_read, writer, max_bytes) do
        {:ok, total_bytes, conn_final}
      else
        {:error, reason} -> {:error, reason, conn_after}
        {:error, reason, conn_final} -> {:error, reason, conn_final}
      end
    end
  end

  defp handle_device_result({:error, reason}, conn, _opts, _writer, _max_bytes) do
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

  def drain(conn, opts \\ []) do
    max_bytes = Keyword.get(opts, :max_bytes, @max_upload_bytes)
    merged_opts = merged_opts(conn, opts, max_bytes)

    result =
      case read_conn_body(conn, plug_read_opts(merged_opts)) do
        {:ok, read_result} -> handle_read_result(read_result, conn, merged_opts, :discard, max_bytes)
        {:exception, error, _stacktrace} -> normalize_read_exception(error, conn)
      end

    case result do
      {:ok, :discarded, conn_after} -> {:ok, conn_after}
      {:ok, conn_after, _bytes_read} -> {:ok, conn_after}
      {:error, _reason, conn_after} -> {:error, conn_after}
    end
  end

  defp handle_read_result(result, conn, opts, mode, max_bytes) do
    case result do
      {:ok, body, conn_after} ->
        if byte_size(body) > max_bytes do
          {:error, :too_large, conn_after}
        else
          case mode do
            :store -> {:ok, body, conn_after}
            :discard -> {:ok, :discarded, conn_after}
          end
        end

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

  defp normalize_transport_error(%{error: :timeout}, conn), do: {:error, :timeout, conn}
  defp normalize_transport_error(_error, conn), do: {:error, :cancelled, conn}

  defp read_chunks(conn, opts, _first_chunk, bytes_read, :discard, max_bytes) do
    read_loop(conn, opts, bytes_read, fn _chunk -> :ok end, max_bytes)
  end

  defp read_chunks(conn, opts, first_chunk, bytes_read, :store, max_bytes) do
    tmp_path = tmp_path(opts)

    case File.open(tmp_path, [:write, :binary]) do
      {:ok, device} ->
        writer = fn chunk -> :file.write(device, chunk) end

        case writer.(first_chunk) do
          :ok ->
            case read_loop(conn, opts, bytes_read, writer, max_bytes) do
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

  defp read_loop(conn, opts, bytes_read, writer, max_bytes) do
    chunk_opts = Keyword.put(opts, :read_timeout, chunk_timeout(opts))

    case read_conn_body(conn, plug_read_opts(chunk_opts)) do
      {:ok, result} -> handle_loop_result(result, conn, opts, bytes_read, writer, max_bytes)
      {:exception, error, _stacktrace} -> normalize_read_exception(error, conn)
    end
  end

  defp read_conn_body(conn, opts) do
    {:ok, Plug.Conn.read_body(conn, opts)}
  rescue
    e in [Bandit.HTTPError, Bandit.TransportError] -> {:exception, e, __STACKTRACE__}
  end

  defp normalize_read_exception(%Bandit.HTTPError{}, conn), do: {:error, :cancelled, conn}
  defp normalize_read_exception(error, conn), do: normalize_transport_error(error, conn)

  defp handle_loop_result(result, conn, opts, bytes_read, writer, max_bytes) do
    case result do
      {:ok, "", conn_after} ->
        {:ok, conn_after, bytes_read}

      {:ok, chunk, conn_after} ->
        write_chunk(conn_after, opts, bytes_read, chunk, writer, max_bytes, false)

      {:more, chunk, conn_after} ->
        write_chunk(conn_after, opts, bytes_read, chunk, writer, max_bytes, true)

      {:error, reason} ->
        normalize_error(reason, conn)
    end
  end

  defp write_chunk(conn, opts, bytes_read, chunk, writer, max_bytes, recurse?) do
    bytes = bytes_read + byte_size(chunk)

    if bytes > max_bytes do
      {:error, :too_large, conn}
    else
      case writer.(chunk) do
        :ok ->
          if recurse? do
            read_loop(conn, opts, bytes, writer, max_bytes)
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

  defp merged_opts(conn, opts, max_bytes) do
    conn.private
    |> Map.get(:body_read_opts, @default_opts)
    |> Keyword.merge(opts)
    |> normalize_length(max_bytes)
    |> then(&TuistCommon.BodyReader.read_opts(conn, &1))
  end

  defp normalize_length(opts, max_bytes) do
    length =
      opts
      |> Keyword.get(:length, Keyword.get(opts, :read_length, @default_read_length))
      |> min(max_bytes)

    Keyword.put(opts, :length, length)
  end

  defp plug_read_opts(opts) do
    Keyword.drop(opts, [:max_bytes, :tmp_dir])
  end

  defp chunk_timeout(opts) do
    TuistCommon.BodyReader.chunk_timeout(opts)
  end

  defp enforce_content_length(result, nil), do: result

  defp enforce_content_length({:ok, body, conn}, expected_length) when is_binary(body) do
    if byte_size(body) == expected_length do
      {:ok, body, conn}
    else
      {:error, :truncated, conn}
    end
  end

  defp enforce_content_length({:ok, {:file, tmp_path} = data, conn}, expected_length) do
    case File.stat(tmp_path) do
      {:ok, %File.Stat{size: size}} when size == expected_length ->
        {:ok, data, conn}

      _ ->
        File.rm(tmp_path)
        {:error, :truncated, conn}
    end
  end

  defp enforce_content_length(other, _expected_length), do: other

  defp enforce_device_content_length(result, nil), do: result

  defp enforce_device_content_length({:ok, bytes, conn}, expected_length) when bytes == expected_length,
    do: {:ok, bytes, conn}

  defp enforce_device_content_length({:ok, _bytes, conn}, _expected_length), do: {:error, :truncated, conn}

  defp enforce_device_content_length(other, _expected_length), do: other
end
