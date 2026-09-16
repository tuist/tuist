defmodule Cache.ContentDigest do
  @moduledoc """
  Client-declared SHA-256 digests of artifact bytes.

  An uploader declares the lowercase hex SHA-256 of what it sends: in the
  `tuist-checksum-sha256` request header on single-request uploads, and in the
  completion body on multipart module uploads. The server checks the bytes it
  received against it before persisting, stores it with the artifact, and
  serves it back under the same header so a downloader can check the bytes it
  receives. Artifact keys are derived from build inputs, not from content, so
  the declared digest is the only claim the bytes can be checked against.

  The server never computes a digest of bytes it already holds and serves that
  instead: it would certify whatever damage those bytes carry.
  """

  import Plug.Conn, only: [get_req_header: 2, put_resp_header: 3]

  @header "tuist-checksum-sha256"
  @read_bytes 1024 * 1024

  def header, do: @header

  @doc """
  The digest a request declares in the `tuist-checksum-sha256` header: `{:ok, nil}`
  when it declares none, `{:error, :invalid_checksum}` when the value is not 64
  hex characters.
  """
  def declared(conn) do
    conn
    |> get_req_header(@header)
    |> List.first()
    |> normalize()
  end

  @doc """
  Normalizes a declared digest to lowercase hex, or rejects it.
  """
  def normalize(nil), do: {:ok, nil}

  def normalize(value) when is_binary(value) do
    normalized = String.downcase(value)

    if Regex.match?(~r/\A[0-9a-f]{64}\z/, normalized),
      do: {:ok, normalized},
      else: {:error, :invalid_checksum}
  end

  def normalize(_value), do: {:error, :invalid_checksum}

  @doc """
  Checks a body read by `Cache.BodyReader` (a binary, or `{:file, path}`) or a
  file path against a declared digest. Nothing declared passes.
  """
  def verify(_data, nil), do: :ok
  def verify({:file, path}, expected), do: verify_path(path, expected)
  def verify(data, expected) when is_binary(data), do: compare({:ok, sha256(data)}, expected)

  def verify_path(_path, nil), do: :ok
  def verify_path(path, expected), do: compare(sha256_file(path), expected)

  @doc """
  Adds the `tuist-checksum-sha256` response header when the artifact has a digest.
  """
  def put_header(conn, nil), do: conn
  def put_header(conn, content_sha256), do: put_resp_header(conn, @header, content_sha256)

  def mismatch_message(expected, actual) do
    "Body does not match #{@header}: declared #{expected}, received #{actual}"
  end

  defp compare({:ok, expected}, expected), do: :ok
  defp compare({:ok, actual}, expected), do: {:error, {:checksum_mismatch, expected, actual}}
  defp compare({:error, _reason} = error, _expected), do: error

  defp sha256(data), do: :sha256 |> :crypto.hash(data) |> Base.encode16(case: :lower)

  defp sha256_file(path) do
    case File.open(path, [:read, :binary, :raw], &hash_device(&1, :crypto.hash_init(:sha256))) do
      {:ok, result} -> result
      {:error, _reason} = error -> error
    end
  end

  defp hash_device(device, state) do
    case :file.read(device, @read_bytes) do
      {:ok, chunk} -> hash_device(device, :crypto.hash_update(state, chunk))
      :eof -> {:ok, state |> :crypto.hash_final() |> Base.encode16(case: :lower)}
      {:error, _reason} = error -> error
    end
  end
end
