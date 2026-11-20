defmodule LuftServer.Notifications.EncryptedBinary do
  @moduledoc false
  use Ecto.Type

  @salt "luft notification token v1"
  def type, do: :binary
  def cast(value) when is_binary(value), do: {:ok, value}
  def cast(_), do: :error

  def dump(value) when is_binary(value),
    do: {:ok, Plug.Crypto.encrypt(secret(), @salt, value, max_age: :infinity)}

  def dump(_), do: :error

  def load(value) when is_binary(value),
    do: Plug.Crypto.decrypt(secret(), @salt, value, max_age: :infinity)

  def load(_), do: :error

  defp secret,
    do:
      :luft_server
      |> Application.fetch_env!(LuftServerWeb.Endpoint)
      |> Keyword.fetch!(:secret_key_base)
end
