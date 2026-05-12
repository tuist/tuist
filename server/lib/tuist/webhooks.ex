defmodule Tuist.Webhooks do
  @moduledoc """
  Outbound webhook delivery for automation actions.

  Webhook actions live inside an automation's `trigger_actions` array (Stripe-
  style envelope sent over HTTPS, HMAC-SHA256 signed). Each action stores
  its destination URL in plaintext and its signing secret as Cloak-encrypted
  ciphertext base64-encoded for JSON — Cloak's Ecto types don't apply to map
  columns, so we encrypt by hand in the same shape used by
  `Tuist.Slack.encrypt_webhook_url/1`.

  The action itself is fired through `Tuist.Automations.Actions.SendWebhookAction`,
  which enqueues a `Tuist.Webhooks.Workers.DeliveryWorker` Oban job. The
  worker performs the actual POST with retries on the RFC schedule
  (1m → 5m → 30m → 2h → 8h → 24h).
  """

  alias Tuist.Webhooks.Signature

  @doc """
  Encrypts a signing secret for storage inside a JSON column. The result
  is base64-encoded ciphertext.
  """
  def encrypt_signing_secret(secret) when is_binary(secret) do
    {:ok, ciphertext} = Tuist.Vault.encrypt(secret)
    {:ok, Base.encode64(ciphertext)}
  end

  @doc """
  Decrypts a signing secret produced by `encrypt_signing_secret/1`.
  """
  def decrypt_signing_secret(encoded) when is_binary(encoded) do
    with {:ok, ciphertext} <- Base.decode64(encoded),
         {:ok, plaintext} <- Tuist.Vault.decrypt(ciphertext) do
      {:ok, plaintext}
    else
      _ -> {:error, :invalid_signing_secret}
    end
  end

  def decrypt_signing_secret(_), do: {:error, :invalid_signing_secret}

  @doc """
  Generates a fresh signing secret and returns it both in plaintext (to
  show the user once) and encrypted (to persist).
  """
  def generate_signing_secret do
    plaintext = Signature.generate_secret()
    {:ok, encrypted} = encrypt_signing_secret(plaintext)
    %{plaintext: plaintext, encrypted: encrypted}
  end

  @doc """
  Returns true when the URL is a syntactically valid HTTPS URL with a host
  component. Used to validate user-supplied destinations before persisting.
  """
  def valid_webhook_url?(url) when is_binary(url) do
    case URI.parse(url) do
      %URI{scheme: "https", host: host} when is_binary(host) and host != "" -> true
      _ -> false
    end
  end

  def valid_webhook_url?(_), do: false
end
