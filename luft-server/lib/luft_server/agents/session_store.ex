defmodule LuftServer.Agents.SessionStore do
  @moduledoc """
  Encrypted durable conversation and journal storage. Condukt fences writes by
  lease epoch. AES-256-GCM uses a separate domain key derived from Luft's
  endpoint secret, never upstream Tuist's vault. Keep that secret stable across
  replicas and releases; rotating it makes existing journals unreadable.
  """
  alias Condukt.SessionStore.ObjectStore
  alias Plug.Crypto.KeyGenerator

  def store(kind, id, epoch) do
    {ObjectStore,
     [
       bucket: bucket(),
       prefix: prefix(kind),
       key: id,
       epoch: epoch,
       encrypt: &encrypt/1,
       decrypt: &decrypt/1
     ]}
  end

  def delete(kind, id) do
    {module, config} = bucket()

    with {:ok, keys} <- module.list(config, "#{prefix(kind)}/#{id}/", nil) do
      Enum.reduce_while(keys, :ok, fn key, :ok ->
        case module.delete(config, key) do
          :ok -> {:cont, :ok}
          error -> {:halt, error}
        end
      end)
    end
  end

  defp prefix(kind), do: "agents/#{kind}"

  defp bucket do
    :luft_server
    |> Application.get_env(__MODULE__, [])
    |> Keyword.get(:bucket, {LuftServer.Agents.Bucket, []})
  end

  defp encrypt(plaintext) do
    iv = :crypto.strong_rand_bytes(12)

    {ciphertext, tag} =
      :crypto.crypto_one_time_aead(
        :aes_256_gcm,
        key(),
        iv,
        plaintext,
        "luft-agent-session-v1",
        true
      )

    <<1, iv::binary, tag::binary, ciphertext::binary>>
  end

  defp decrypt(<<1, iv::binary-12, tag::binary-16, ciphertext::binary>>) do
    case :crypto.crypto_one_time_aead(
           :aes_256_gcm,
           key(),
           iv,
           ciphertext,
           "luft-agent-session-v1",
           tag,
           false
         ) do
      plaintext when is_binary(plaintext) -> plaintext
      :error -> raise ArgumentError, "invalid agent session ciphertext"
    end
  end

  defp decrypt(_), do: raise(ArgumentError, "invalid agent session ciphertext")

  defp key do
    secret = Application.fetch_env!(:luft_server, LuftServerWeb.Endpoint)[:secret_key_base]

    KeyGenerator.generate(secret, "luft agent session journals v1",
      length: 32,
      cache: Plug.Crypto.Keys
    )
  end
end
