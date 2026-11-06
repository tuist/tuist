defmodule Tuist.Kura.VolumeKeys.HKDF do
  @moduledoc """
  HKDF-SHA256 (RFC 5869).
  """

  @hash_length 32

  def derive(ikm, salt, info, length) when is_binary(ikm) and is_binary(salt) and is_binary(info) and length > 0 do
    salt
    |> extract(ikm)
    |> expand(info, length)
  end

  def extract(salt, ikm), do: :crypto.mac(:hmac, :sha256, salt, ikm)

  def expand(prk, info, length) when length <= 255 * @hash_length do
    blocks = div(length + @hash_length - 1, @hash_length)

    {okm, _previous} =
      Enum.reduce(1..blocks, {<<>>, <<>>}, fn counter, {okm, previous} ->
        block = :crypto.mac(:hmac, :sha256, prk, previous <> info <> <<counter>>)
        {okm <> block, block}
      end)

    binary_part(okm, 0, length)
  end
end
