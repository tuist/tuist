defmodule TuistCommon.BodyReader do
  @moduledoc """
  Shared utilities for reading request bodies with dynamic timeouts.

  This module provides functions to calculate appropriate read timeouts based on
  the expected content length, allowing slower connections to complete uploads
  while still timing out stalled transfers.

  ## Timeout Strategy

  The timeout calculation is inspired by Apache's `mod_reqtimeout` module which
  uses a `MinRate` parameter to extend timeouts based on data throughput:
  https://httpd.apache.org/docs/current/mod/mod_reqtimeout.html

  Key features:
  - **Dynamic initial timeout**: Calculated based on Content-Length and minimum throughput
  - **Maximum timeout cap**: Prevents abuse from spoofed Content-Length headers
  - **Progressive extension**: Timeout resets on each successful chunk read

  ## Security Considerations

  The maximum timeout cap protects against Slow Loris-style attacks where an
  attacker could send a large Content-Length but trickle data very slowly:
  https://www.cloudflare.com/learning/ddos/ddos-attack-tools/slowloris/
  """

  @default_read_timeout 60_000
  @default_max_timeout 600_000
  @default_read_length 262_144
  @default_max_bytes 100_000_000
  @default_min_throughput_bytes_per_sec 50 * 1024

  @doc """
  Reads the request body from the connection with progressive timeouts.

  Uses dynamic timeouts based on Content-Length for the initial read, then
  progressive chunk-based timeouts for subsequent reads (like Apache's MinRate).

  Returns:
  - `{:ok, body, conn}` - Body read successfully
  - `{:error, :timeout, conn}` - Read timed out
  - `{:error, :too_large, conn}` - Body exceeds max_bytes
  - `{:error, :cancelled, conn}` - Client disconnected
  - `{:error, reason, conn}` - Other error

  ## Options

    * `:length` - Maximum bytes to read (default: 100MB)
    * `:read_length` - Bytes to read per chunk (default: 256KB)
    * `:max_bytes` - Maximum allowed body size (default: 100MB)

  """
  def read(conn, opts \\ []) do
    base_opts = [length: @default_max_bytes, read_length: @default_read_length]
    merged_opts = Keyword.merge(read_opts(conn, base_opts), opts)
    max_bytes = Keyword.get(opts, :max_bytes, @default_max_bytes)

    conn
    |> Plug.Conn.read_body(merged_opts)
    |> handle_read_result(conn, merged_opts, max_bytes, <<>>)
  rescue
    e in [Bandit.TransportError] ->
      case e do
        %{error: :timeout} -> {:error, :timeout, conn}
        _ -> {:error, :cancelled, conn}
      end
  end

  defp handle_read_result(result, conn, opts, max_bytes, acc) do
    case result do
      {:ok, body, conn_after} ->
        full_body = acc <> body

        if byte_size(full_body) > max_bytes do
          {:error, :too_large, conn_after}
        else
          {:ok, full_body, conn_after}
        end

      {:more, chunk, conn_after} ->
        new_acc = acc <> chunk

        if byte_size(new_acc) > max_bytes do
          {:error, :too_large, conn_after}
        else
          read_next_chunk(conn_after, opts, max_bytes, new_acc)
        end

      {:error, :too_large} ->
        {:error, :too_large, conn}

      {:error, reason} when reason in [:timeout, :econnaborted] ->
        {:error, :timeout, conn}

      {:error, reason} ->
        {:error, reason, conn}
    end
  end

  defp read_next_chunk(conn, opts, max_bytes, acc) do
    chunk_opts = Keyword.put(opts, :read_timeout, chunk_timeout(opts))

    conn
    |> Plug.Conn.read_body(chunk_opts)
    |> handle_read_result(conn, opts, max_bytes, acc)
  rescue
    e in [Bandit.TransportError] ->
      case e do
        %{error: :timeout} -> {:error, :timeout, conn}
        _ -> {:error, :cancelled, conn}
      end
  end

  @doc """
  Calculates a dynamic read timeout based on content length.

  The timeout is calculated to allow a minimum throughput rate, with a floor
  to prevent extremely short timeouts for small uploads and a ceiling to
  prevent abuse from spoofed Content-Length headers.

  ## Options

    * `:min_timeout` - Minimum timeout in milliseconds (default: 60_000 = 1 minute)
    * `:max_timeout` - Maximum timeout in milliseconds (default: 600_000 = 10 minutes)
    * `:min_throughput` - Minimum expected throughput in bytes/second (default: 51_200 = 50KB/s)

  ## Examples

      iex> TuistCommon.BodyReader.calculate_timeout(1_000_000)
      60_000

      iex> TuistCommon.BodyReader.calculate_timeout(25_000_000)
      500_000

      # Capped at max_timeout for very large content
      iex> TuistCommon.BodyReader.calculate_timeout(100_000_000_000)
      600_000

  """
  def calculate_timeout(content_length, opts \\ []) do
    min_timeout = Keyword.get(opts, :min_timeout, @default_read_timeout)
    max_timeout = Keyword.get(opts, :max_timeout, @default_max_timeout)
    min_throughput = Keyword.get(opts, :min_throughput, @default_min_throughput_bytes_per_sec)

    calculated_timeout = div(content_length * 1000, min_throughput)

    calculated_timeout
    |> max(min_timeout)
    |> min(max_timeout)
  end

  @doc """
  Returns read options with a dynamic timeout based on the request's Content-Length.

  If no Content-Length header is present, returns the default options.

  ## Options

    * `:length` - Maximum bytes to read total (default: from base_opts or 8MB)
    * `:read_length` - Bytes to read per chunk (default: 262_144 = 256KB)
    * `:read_timeout` - Base timeout, will be overridden by dynamic calculation
    * `:min_timeout` - Minimum timeout in milliseconds (default: 60_000)
    * `:max_timeout` - Maximum timeout in milliseconds (default: 600_000)
    * `:min_throughput` - Minimum expected throughput in bytes/second (default: 51_200)

  ## Examples

      conn = %Plug.Conn{req_headers: [{"content-length", "10000000"}]}
      opts = TuistCommon.BodyReader.read_opts(conn)
      # Returns opts with ~200s timeout for 10MB at 50KB/s

  """
  def read_opts(conn, base_opts \\ []) do
    base_opts =
      Keyword.merge(
        [read_length: @default_read_length, read_timeout: @default_read_timeout],
        base_opts
      )

    case get_content_length(conn) do
      nil ->
        cleanup_internal_opts(base_opts)

      content_length ->
        timeout_opts = Keyword.take(base_opts, [:min_timeout, :max_timeout, :min_throughput])
        dynamic_timeout = calculate_timeout(content_length, timeout_opts)

        base_opts
        |> cleanup_internal_opts()
        |> Keyword.put(:read_timeout, dynamic_timeout)
    end
  end

  defp cleanup_internal_opts(opts) do
    opts
    |> Keyword.delete(:min_timeout)
    |> Keyword.delete(:max_timeout)
    |> Keyword.delete(:min_throughput)
  end

  @doc """
  Calculates a progressive timeout for the next chunk read.

  This implements a strategy similar to Apache's `mod_reqtimeout` MinRate:
  the timeout for each chunk is based on the chunk size and minimum throughput,
  with floor and ceiling values.

  This is useful when reading in a loop where each chunk read should have
  its own timeout based on expected data rate, rather than a single large
  timeout for the entire body.

  ## Options

    * `:read_length` - Expected chunk size in bytes (default: 262_144 = 256KB)
    * `:min_timeout` - Minimum timeout per chunk in milliseconds (default: 15_000 = 15s)
    * `:max_timeout` - Maximum timeout per chunk in milliseconds (default: 60_000 = 1 minute)
    * `:min_throughput` - Minimum expected throughput in bytes/second (default: 51_200 = 50KB/s)

  ## Examples

      # For a 256KB chunk at 50KB/s = ~5 seconds, but min is 15s
      iex> TuistCommon.BodyReader.chunk_timeout()
      15_000

      # For a 1MB chunk at 50KB/s = ~20 seconds
      iex> TuistCommon.BodyReader.chunk_timeout(read_length: 1_000_000)
      20_000

  """
  def chunk_timeout(opts \\ []) do
    read_length = Keyword.get(opts, :read_length, @default_read_length)
    min_timeout = Keyword.get(opts, :min_timeout, 15_000)
    max_timeout = Keyword.get(opts, :max_timeout, @default_read_timeout)
    min_throughput = Keyword.get(opts, :min_throughput, @default_min_throughput_bytes_per_sec)

    calculated_timeout = div(read_length * 1000, min_throughput)

    calculated_timeout
    |> max(min_timeout)
    |> min(max_timeout)
  end

  @doc """
  Gets the Content-Length header value from a connection.

  Returns `nil` if the header is not present or cannot be parsed.
  """
  def get_content_length(conn) do
    with [value] <- Plug.Conn.get_req_header(conn, "content-length"),
         {length, ""} when length >= 0 <- Integer.parse(value) do
      length
    else
      _ -> nil
    end
  end
end
