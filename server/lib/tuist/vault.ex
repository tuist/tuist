defmodule Tuist.Vault do
  @moduledoc false
  use Cloak.Vault, otp_app: :tuist

  @impl GenServer
  def init(config) do
    config =
      Keyword.put(config, :ciphers, default_ciphers(config[:key]))

    {:ok, config}
  end

  defp default_ciphers(key) do
    [
      default: {Cloak.Ciphers.AES.GCM, tag: "AES.GCM.V1", key: decode_env!(key)},
      retired: []
    ]
  end

  defp decode_env!(nil), do: nil

  defp decode_env!({module, function, args}) do
    # Call the function to get the actual key value
    key = apply(module, function, args)
    decode_env!(key)
  end

  defp decode_env!(key) when is_binary(key) do
    # AES-GCM requires exactly 32 bytes for the encryption key
    # If the key is already the right length, use it directly
    # Otherwise, take the first 32 bytes or pad with zeros
    case byte_size(key) do
      size when size >= 32 -> binary_part(key, 0, 32)
      size -> key <> :binary.copy(<<0>>, 32 - size)
    end
  end
end
