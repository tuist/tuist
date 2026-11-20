defmodule LuftServer.Threads.EncryptedBinary do
  @moduledoc """
  Authenticated, non-expiring storage for thread checkpoints and tool results.

  Uses Luft's endpoint secret with a dedicated salt. Legacy Tuist.Vault values
  must be decrypted at their source and re-encrypted through this type during
  import; ciphertext from the old key/format is never accepted as live data.
  Rotating SECRET_KEY_BASE requires decrypting and re-encrypting stored values.
  """
  use Ecto.Type

  @salt "luft thread encrypted binary v1"

  def type, do: :binary

  def cast(value) when is_binary(value), do: {:ok, value}
  def cast(_value), do: :error

  def dump(value) when is_binary(value),
    do: {:ok, Plug.Crypto.encrypt(secret(), @salt, value, max_age: :infinity)}

  def dump(_value), do: :error

  def load(value) when is_binary(value) do
    case Plug.Crypto.decrypt(secret(), @salt, value, max_age: :infinity) do
      {:ok, plaintext} when is_binary(plaintext) -> {:ok, plaintext}
      _ -> :error
    end
  end

  def load(_value), do: :error

  defp secret do
    :luft_server
    |> Application.fetch_env!(LuftServerWeb.Endpoint)
    |> Keyword.fetch!(:secret_key_base)
  end
end
