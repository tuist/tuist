defmodule TuistWeb.Plugs.DeflateBodyReader do
  @moduledoc """
  The `Plug.Parsers` body reader, adding support for request bodies a client
  compressed with `Content-Encoding: deflate`: raw DEFLATE, which is what Apple's
  `NSData.compressed(using: .zlib)` produces. The CLI compresses large test run
  uploads that carry code coverage, which shrink by an order of magnitude.

  Both the compressed body and its decompressed size are held to the parser's
  `:length`, so a small compressed body cannot expand past the limit an
  uncompressed one has.
  """

  def read_body(conn, opts) do
    case Plug.Conn.get_req_header(conn, "content-encoding") do
      ["deflate"] -> read_deflated_body(conn, opts)
      _ -> Plug.Conn.read_body(conn, opts)
    end
  end

  defp read_deflated_body(conn, opts) do
    limit = Keyword.get(opts, :length, 8_000_000)

    with {:ok, compressed, conn} <- read_compressed_body(conn, opts, limit, [], 0) do
      case inflate(compressed, limit) do
        {:ok, body} -> {:ok, body, conn}
        :too_large -> {:more, "", conn}
        :invalid -> {:error, :invalid_deflate_body}
      end
    end
  end

  defp read_compressed_body(conn, opts, limit, acc, size) do
    case Plug.Conn.read_body(conn, opts) do
      {:ok, chunk, conn} ->
        {:ok, IO.iodata_to_binary([acc, chunk]), conn}

      {:more, chunk, conn} when size + byte_size(chunk) <= limit ->
        read_compressed_body(conn, opts, limit, [acc, chunk], size + byte_size(chunk))

      {:more, chunk, conn} ->
        {:more, chunk, conn}

      {:error, reason} ->
        {:error, reason}
    end
  end

  defp inflate(compressed, limit) do
    z = :zlib.open()

    try do
      :ok = :zlib.inflateInit(z, -15)
      inflate_chunks(z, :zlib.safeInflate(z, compressed), [], 0, limit)
    rescue
      ErlangError -> :invalid
    after
      :zlib.close(z)
    end
  end

  defp inflate_chunks(z, {status, output}, acc, size, limit) do
    size = size + IO.iodata_length(output)

    cond do
      size > limit -> :too_large
      status == :finished -> {:ok, IO.iodata_to_binary([acc, output])}
      true -> inflate_chunks(z, :zlib.safeInflate(z, []), [acc, output], size, limit)
    end
  end
end
