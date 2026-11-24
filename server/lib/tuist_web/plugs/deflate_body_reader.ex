defmodule TuistWeb.Plugs.DeflateBodyReader do
  @moduledoc """
  The `Plug.Parsers` body reader, adding support for request bodies a client
  compressed with `Content-Encoding: deflate`: raw DEFLATE, which is what Apple's
  `NSData.compressed(using: .zlib)` produces. The CLI compresses large test run
  uploads that carry code coverage, which shrink by an order of magnitude.
  `Content-Encoding: gzip` is inflated the same way, for OTLP exporters and
  Sentry SDKs; controllers that read a body the parsers pass through call
  `read_body/2` themselves to get both.

  Both the compressed body and its decompressed size are held to the parser's
  `:length`, so a small compressed body cannot expand past the limit an
  uncompressed one has.
  """

  def read_body(conn, opts) do
    opts =
      cond do
        network_report?(conn) -> Keyword.put(opts, :length, 8_000_000)
        # Luft's batches encode to at most 1 MiB; never parse more JSON than that needs.
        match?(["api", "telemetry" | _], conn.path_info) -> Keyword.put(opts, :length, 4_000_000)
        true -> opts
      end

    case Plug.Conn.get_req_header(conn, "content-encoding") do
      ["deflate"] -> read_deflated_body(conn, opts, -15)
      # OTLP/HTTP receivers must take gzip, and Sentry SDKs send it.
      ["gzip"] -> read_deflated_body(conn, opts, 31)
      _ -> Plug.Conn.read_body(conn, opts)
    end
  end

  defp network_report?(conn) do
    conn.method == "POST" and Plug.Conn.get_req_header(conn, "authorization") == [] and
      case conn.path_info do
        ["api", "projects", _, _, "builds"] -> true
        ["api", "projects", _, _, "tests"] -> true
        ["api", "projects", _, _, system, "builds"] when system in ["gradle", "xcode", "mix"] -> true
        ["api", "projects", _, _, "bazel", "publishing"] -> true
        _ -> false
      end
  end

  defp read_deflated_body(conn, opts, window_bits) do
    limit = Keyword.get(opts, :length, 8_000_000)

    with {:ok, compressed, conn} <- read_compressed_body(conn, opts, limit, [], 0) do
      case inflate(compressed, limit, window_bits) do
        {:ok, body} -> {:ok, body, conn}
        :too_large -> {:more, "", conn}
        :invalid -> {:error, :invalid_deflate_body}
      end
    end
  end

  defp read_compressed_body(conn, opts, limit, acc, size) do
    case Plug.Conn.read_body(conn, opts) do
      {:ok, chunk, conn} when size + byte_size(chunk) <= limit ->
        {:ok, IO.iodata_to_binary([acc, chunk]), conn}

      {:ok, chunk, conn} ->
        {:more, chunk, conn}

      {:more, chunk, conn} when size + byte_size(chunk) <= limit ->
        read_compressed_body(conn, opts, limit, [acc, chunk], size + byte_size(chunk))

      {:more, chunk, conn} ->
        {:more, chunk, conn}

      {:error, reason} ->
        {:error, reason}
    end
  end

  defp inflate(compressed, limit, window_bits) do
    z = :zlib.open()

    try do
      :ok = init_inflate(z, window_bits)
      inflate_chunks(z, :zlib.safeInflate(z, compressed), [], 0, limit)
    rescue
      ErlangError -> :invalid
    after
      :zlib.close(z)
    end
  end

  # A gzip body may hold several members, which decode to their concatenation
  # (RFC 1952); `:reset` starts the next member instead of ignoring it, as
  # `:zlib.gunzip/1` does, so bytes after a member must be another member.
  defp init_inflate(z, 31), do: :zlib.inflateInit(z, 31, :reset)
  defp init_inflate(z, window_bits), do: :zlib.inflateInit(z, window_bits)

  defp inflate_chunks(z, {status, output}, acc, size, limit) do
    size = size + IO.iodata_length(output)

    cond do
      size > limit ->
        :too_large

      # `safeInflate` also reports `:finished` when the input ends mid-stream;
      # `inflateEnd` raises unless the stream (and a gzip trailer) is complete.
      status == :finished ->
        :ok = :zlib.inflateEnd(z)
        {:ok, IO.iodata_to_binary([acc, output])}

      true ->
        inflate_chunks(z, :zlib.safeInflate(z, []), [acc, output], size, limit)
    end
  end
end
