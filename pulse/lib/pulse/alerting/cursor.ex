defmodule Pulse.Alerting.Cursor do
  @moduledoc false
  alias Pulse.Alerting.Canonical
  alias Pulse.Runtime

  @ttl 600

  def seal(principal, id, ref, opts \\ []) do
    nonce = :crypto.strong_rand_bytes(12)
    bytes = Canonical.encode(%{"ref" => ref, "issued_at" => System.system_time(:second)})
    {cipher, tag} = :crypto.crypto_one_time_aead(:aes_256_gcm, key(opts), nonce, bytes, aad(principal, id), 16, true)
    Base.url_encode64(nonce <> tag <> cipher, padding: false)
  end

  def open(nil, _principal, _id, _opts), do: {:ok, nil}

  def open(token, principal, id, opts) when is_binary(token) and byte_size(token) <= 4096 do
    with {:ok, <<nonce::binary-size(12), tag::binary-size(16), cipher::binary>>} <-
           Base.url_decode64(token, padding: false),
         bytes when is_binary(bytes) <-
           :crypto.crypto_one_time_aead(:aes_256_gcm, key(opts), nonce, cipher, aad(principal, id), tag, false),
         {:ok, %{"ref" => ref, "issued_at" => time}} <- Pulse.JSON.decode(bytes),
         true <- valid_time?(time) do
      {:ok, ref}
    else
      _ -> {:error, :reset_required}
    end
  end

  def open(_, _, _, _), do: {:error, :reset_required}

  defp valid_time?(time) do
    now = System.system_time(:second)
    is_integer(time) and time <= now and now - time <= @ttl
  end

  defp aad(principal, id), do: Canonical.encode([principal.tenant, principal.id, Enum.sort(principal.capabilities), id])

  defp key(opts) do
    secret = Keyword.get(opts, :cursor_secret, Runtime.fetch_env!(:pulse, PulseWeb.Endpoint)[:secret_key_base])
    :crypto.hash(:sha256, "pulse-alerting-audit-v1:" <> secret)
  end
end
