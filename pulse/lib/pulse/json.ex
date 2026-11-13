defmodule Pulse.JSON do
  @moduledoc """
  JSON encoding and decoding with a Rust fast path and Elixir's `JSON`
  module as the reference.

  Configured as Phoenix's JSON library (`config :phoenix, :json_library`),
  so it handles every request body `Plug.Parsers` decodes and every
  response `Phoenix.Controller.json/2` encodes.

  The Rust path (`Pulse.Codec.NIF`) only answers when it can guarantee
  the same result as `JSON`; for anything else (structs, bignums, float
  or colliding map keys, duplicate object keys, invalid input, and so on)
  it defers and this module calls `JSON`. Errors therefore always come
  from `JSON`, with its exception types and messages.

  Decoded strings longer than 64 bytes are sub-binaries of the input
  rather than copies. Anything that keeps decoded data long after the
  input should `:binary.copy/1` the strings it keeps.
  """

  alias Pulse.Codec.NIF

  # Inputs up to this size decode on the calling scheduler (well under a
  # millisecond); larger ones go to a dirty CPU scheduler.
  @inline_decode_bytes 64 * 1024

  # Encodes start on the calling scheduler and move to a dirty one once
  # the output passes this many bytes. The abandoned work is bounded by
  # the budget.
  @inline_encode_budget 64 * 1024

  @spec decode(binary()) :: {:ok, term()} | {:error, term()}
  def decode(binary) when is_binary(binary) do
    case nif_decode(binary) do
      {:ok, term} -> {:ok, term}
      :fallback -> JSON.decode(binary)
    end
  end

  @spec decode!(binary()) :: term()
  def decode!(binary) when is_binary(binary) do
    case nif_decode(binary) do
      {:ok, term} -> term
      :fallback -> JSON.decode!(binary)
    end
  end

  @doc """
  Copy every string of a decoded or projected term that is a sub-binary of a larger
  binary, so the term neither pins its input nor counts the whole input once
  per string against a process cap that includes shared binaries.
  """
  @spec detach(term()) :: term()
  def detach(binary) when is_binary(binary) do
    if :binary.referenced_byte_size(binary) > byte_size(binary), do: :binary.copy(binary), else: binary
  end

  def detach(list) when is_list(list), do: Enum.map(list, &detach/1)
  def detach(tuple) when is_tuple(tuple), do: tuple |> Tuple.to_list() |> Enum.map(&detach/1) |> List.to_tuple()
  def detach(%{} = map), do: :maps.fold(fn key, value, acc -> Map.put(acc, detach(key), detach(value)) end, %{}, map)
  def detach(other), do: other

  @spec encode!(term()) :: binary()
  def encode!(term) do
    case nif_encode(term) do
      {:ok, binary} -> binary
      :fallback -> JSON.encode!(term)
    end
  end

  @spec encode_to_iodata!(term()) :: iodata()
  def encode_to_iodata!(term) do
    case nif_encode(term) do
      {:ok, binary} -> binary
      :fallback -> JSON.encode_to_iodata!(term)
    end
  end

  defp nif_decode(binary) when byte_size(binary) <= @inline_decode_bytes, do: NIF.json_decode(binary)
  defp nif_decode(binary), do: NIF.json_decode_dirty(binary)

  defp nif_encode(term) do
    case NIF.json_encode(term, @inline_encode_budget) do
      :too_big -> NIF.json_encode_dirty(term)
      result -> result
    end
  end
end
