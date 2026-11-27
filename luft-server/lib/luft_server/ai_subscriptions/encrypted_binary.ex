defmodule LuftServer.AISubscriptions.EncryptedBinary do
  @moduledoc """
  Authenticated storage for AI subscription credentials, with Luft's endpoint
  secret and a dedicated salt. A value that no longer decrypts, such as after
  SECRET_KEY_BASE rotates, loads as nil with a warning: the credential reads
  as disconnected and people connect again, instead of every read of the row
  failing.
  """
  use Ecto.Type

  require Logger

  @salt "luft ai subscription credential v1"

  def type, do: :binary

  def cast(value) when is_binary(value), do: {:ok, value}
  def cast(_value), do: :error

  def dump(value) when is_binary(value),
    do: {:ok, Plug.Crypto.encrypt(secret(), @salt, value, max_age: :infinity)}

  def dump(_value), do: :error

  def load(value) when is_binary(value) do
    case Plug.Crypto.decrypt(secret(), @salt, value, max_age: :infinity) do
      {:ok, plaintext} when is_binary(plaintext) ->
        {:ok, plaintext}

      _ ->
        # Never the value: a warning per read shows a rotated or wrong
        # SECRET_KEY_BASE before people find their connections gone.
        Logger.warning(
          "AI subscription credential could not be decrypted; it reads as disconnected. Check SECRET_KEY_BASE."
        )

        {:ok, nil}
    end
  end

  def load(_value), do: :error

  defp secret,
    do:
      :luft_server
      |> Application.fetch_env!(LuftServerWeb.Endpoint)
      |> Keyword.fetch!(:secret_key_base)
end
