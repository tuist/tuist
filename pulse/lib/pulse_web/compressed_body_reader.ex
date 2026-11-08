defmodule PulseWeb.CompressedBodyReader do
  @moduledoc """
  Body reader for `Plug.Parsers` that transparently decompresses a
  `Content-Encoding: gzip` request body before parsing.

  Both Loki push and Prometheus `remote_write` agents (and OTLP/HTTP
  senders configured to compress) commonly ship gzipped payloads, and
  Plug's built-in JSON parser needs plain bytes to hand to the decoder.

  Sentry's raw body reader additionally opts into zlib-wrapped deflate with
  `:deflate` and standard Zstandard frames with `:zstd`. Other callers retain
  gzip-only decompression. Both use the same incremental output budget and
  require a complete stream/frame without trailing bytes or a preset dictionary.

  Snappy is intentionally not handled here — Loki's snappy-framed
  protobuf variant sits on a different content-type and needs its own
  decoder anyway.

  The reader forwards a `{:more, ...}` return unchanged. If the body
  exceeds Plug.Parsers's configured length limit, the parser rejects
  it with 413 — a decompressor cannot invent the missing bytes.

  The compressed length limit alone does not bound memory, since gzip
  expands by orders of magnitude. Inflation therefore runs incrementally and
  aborts with `Plug.Parsers.RequestTooLargeError` (413) once the output
  passes `:max_decompressed_bytes`, so a gzip bomb is never fully
  materialised. The limit is the `:max_decompressed_bytes` option of
  `config :pulse, PulseWeb.CompressedBodyReader` and defaults to 16 MiB, the
  same ceiling the Snappy receivers apply.
  """

  alias Plug.Parsers.RequestTooLargeError
  alias Pulse.Runtime

  @default_max_decompressed_bytes 16 * 1024 * 1024
  @max_gzip_members 64
  @max_zstd_window 16 * 1024 * 1024

  @spec read_body(Plug.Conn.t(), keyword()) ::
          {:ok, binary(), Plug.Conn.t()}
          | {:more, binary(), Plug.Conn.t()}
          | {:error, term()}
  def read_body(conn, opts) do
    case Plug.Conn.read_body(conn, opts) do
      {:ok, body, conn} ->
        case maybe_decompress(conn, body, opts) do
          {:ok, decompressed} -> {:ok, decompressed, conn}
          {:error, _} = err -> err
        end

      other ->
        other
    end
  end

  @doc false
  def decompress(conn, body) do
    maybe_decompress(conn, body)
  rescue
    RequestTooLargeError -> {:error, :payload_too_large}
  end

  @doc false
  def uncompress(body, max_bytes) do
    output = inflate_member(body, max_bytes, 15, :error)
    {:ok, IO.iodata_to_binary(output)}
  rescue
    e in RequestTooLargeError -> reraise e, __STACKTRACE__
    _ -> {:error, :invalid_deflate}
  end

  defp maybe_decompress(conn, body, opts \\ []) do
    case {Plug.Conn.get_req_header(conn, "content-encoding"), Keyword.get(opts, :deflate), Keyword.get(opts, :zstd)} do
      {["gzip"], _, _} -> gunzip(body)
      {["deflate"], true, _} -> uncompress(body, max_decompressed_bytes())
      {["zstd"], _, true} -> unzstd(body)
      _ -> {:ok, body}
    end
  end

  defp unzstd(body) do
    validate_zstd_frame(body)
    {:ok, context} = :zstd.context(:decompress, %{windowLogMax: 24})

    try do
      {:ok, IO.iodata_to_binary(inflate_zstd(context, body, [], max_decompressed_bytes()))}
    after
      :zstd.close(context)
    end
  rescue
    e in RequestTooLargeError -> reraise e, __STACKTRACE__
    _ -> {:error, :invalid_zstd}
  end

  # OTP's streaming API does not expose the decoder's end-of-frame indicator.
  # Prove the complete standard frame's byte geometry before decoding so that
  # a truncated frame cannot pass merely because its output is already valid JSON.
  # Only complete headers reach get_frame_header/1; it does not reject partial ones.
  defp validate_zstd_frame(<<0x28, 0xB5, 0x2F, 0xFD, descriptor, _::binary>> = body) do
    single? = Bitwise.band(descriptor, 0x20) != 0
    dictionary_bytes = elem({0, 1, 2, 4}, Bitwise.band(descriptor, 3))
    size_bytes = elem({if(single?, do: 1, else: 0), 2, 4, 8}, Bitwise.bsr(descriptor, 6))
    header_bytes = 5 + if(single?, do: 0, else: 1) + dictionary_bytes + size_bytes
    <<header::binary-size(^header_bytes), blocks::binary>> = body

    {:ok, %{frameType: :ZSTD_frame, dictID: 0, windowSize: window, checksumFlag: checksum?}} =
      :zstd.get_frame_header(header)

    if window > @max_zstd_window, do: raise(RequestTooLargeError)
    validate_zstd_blocks(blocks, if(checksum?, do: 4, else: 0))
  end

  defp validate_zstd_blocks(<<block::little-24, rest::binary>>, checksum_bytes) do
    type = Bitwise.band(Bitwise.bsr(block, 1), 3)
    if type == 3, do: raise(ArgumentError, "reserved Zstandard block type")
    bytes = if type == 1, do: 1, else: Bitwise.bsr(block, 3)
    <<_::binary-size(^bytes), rest::binary>> = rest

    if Bitwise.band(block, 1) == 1 do
      true = byte_size(rest) == checksum_bytes
    else
      validate_zstd_blocks(rest, checksum_bytes)
    end
  end

  defp inflate_zstd(context, input, acc, budget) do
    {rest, chunk} =
      case :zstd.stream(context, input) do
        {:continue, rest, chunk} -> {rest, chunk}
        {:continue, chunk} -> {<<>>, chunk}
      end

    budget = budget - byte_size(chunk)
    if budget < 0, do: raise(RequestTooLargeError)

    if rest == <<>> and chunk == <<>> do
      acc
    else
      inflate_zstd(context, rest, [acc, chunk], budget)
    end
  end

  # `:zlib.gunzip/1` semantics, bounded: every concatenated member is
  # inflated, a truncated stream or missing trailer is an error, and one
  # cumulative budget covers all members.
  defp gunzip(<<>>), do: {:error, :invalid_gzip}

  defp gunzip(body) do
    {:ok, IO.iodata_to_binary(inflate_members(body, [], max_decompressed_bytes(), 0))}
  rescue
    e in RequestTooLargeError -> reraise e, __STACKTRACE__
    _ -> {:error, :invalid_gzip}
  end

  defp inflate_members(<<>>, acc, _budget, _members), do: acc
  defp inflate_members(_body, _acc, _budget, @max_gzip_members), do: raise(RequestTooLargeError)

  defp inflate_members(body, acc, budget, members) do
    output = inflate_member(body, budget, 16 + 15, :cut)
    size = IO.iodata_length(output)
    consumed = member_size(body, output)
    rest = binary_part(body, consumed, byte_size(body) - consumed)
    inflate_members(rest, [acc, output], budget - size, members + 1)
  end

  defp inflate_member(body, budget, window_bits, eos_behavior) do
    z = :zlib.open()

    try do
      :zlib.inflateInit(z, window_bits, eos_behavior)
      output = inflate(z, :zlib.safeInflate(z, body), [], 0, budget)
      # Raises `:data_error` when the stream ended early (no trailer).
      :zlib.inflateEnd(z)
      output
    after
      :zlib.close(z)
    end
  end

  defp inflate(z, {status, chunk}, acc, size, max) do
    size = size + IO.iodata_length(chunk)

    cond do
      size > max -> raise RequestTooLargeError
      status == :continue -> inflate(z, :zlib.safeInflate(z, []), [acc, chunk], size, max)
      true -> [acc, chunk]
    end
  end

  # zlib does not report how much input a member consumed, but a gzip member
  # always ends with `CRC32 || ISIZE` of its own output. The member ends at the
  # earliest occurrence of that trailer that is followed by end of input or
  # the next member's magic bytes.
  defp member_size(body, output) do
    trailer = <<:erlang.crc32(output)::little-32, rem(IO.iodata_length(output), 4_294_967_296)::little-32>>

    member_end(body, trailer, 0)
  end

  defp member_end(body, trailer, offset) do
    case :binary.match(body, trailer, scope: {offset, byte_size(body) - offset}) do
      {pos, len} ->
        next = pos + len

        case binary_part(body, next, min(2, byte_size(body) - next)) do
          <<>> -> next
          <<0x1F, 0x8B>> -> next
          # Consider overlapping candidates; an empty member's zero trailer
          # overlaps the end of its deflate block by one byte.
          _ -> member_end(body, trailer, pos + 1)
        end

      :nomatch ->
        raise "gzip member boundary not found"
    end
  end

  defp max_decompressed_bytes do
    :pulse
    |> Runtime.get_env(__MODULE__, [])
    |> Keyword.get(:max_decompressed_bytes, @default_max_decompressed_bytes)
  end
end
