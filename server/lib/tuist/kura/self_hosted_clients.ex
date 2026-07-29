defmodule Tuist.Kura.SelfHostedClients do
  @moduledoc """
  Issuance and verification of tenant-scoped credentials for self-hosted Kura
  nodes.

  These credentials are the spine of self-hosting: a customer's nodes run
  without Tuist's symmetric JWT verifier secret (which would let them mint
  tokens for any tenant), so they authorize every uncached request against the
  control plane's introspection endpoint using one of these credentials. The
  control plane resolves the credential to its owning account and scopes the
  response to that tenant.
  """
  import Ecto.Query

  alias Tuist.Accounts.Account
  alias Tuist.Billing.Entitlements
  alias Tuist.Environment
  alias Tuist.Kura.SelfHostedClient
  alias Tuist.Repo

  @client_id_prefix "cache"

  @doc "Lists the self-hosted credentials issued for an account."
  def list_self_hosted_clients(%Account{} = account) do
    Repo.all(
      from(c in SelfHostedClient,
        where: c.account_id == ^account.id,
        order_by: [asc: c.inserted_at]
      )
    )
  end

  @doc """
  Issues a tenant-scoped credential for an account and returns the plaintext
  secret exactly once as `{:ok, {client, client_secret}}`. The plaintext is
  never recoverable afterwards.
  """
  def create_self_hosted_client(%Account{} = account, attrs \\ %{}) do
    client_secret = generate_secret()

    encrypted_secret_hash =
      Bcrypt.hash_pwd_salt(client_secret <> Environment.secret_key_password())

    changeset =
      SelfHostedClient.create_changeset(%{
        account_id: account.id,
        client_id: generate_client_id(),
        encrypted_secret_hash: encrypted_secret_hash,
        secret_last_four: SelfHostedClient.last_four(client_secret),
        name: attrs[:name] || attrs["name"]
      })

    case Repo.insert(changeset) do
      {:ok, client} -> {:ok, {client, client_secret}}
      {:error, changeset} -> {:error, changeset}
    end
  end

  @doc "Revokes a credential. Self-hosted nodes using it stop authenticating."
  def revoke_self_hosted_client(%SelfHostedClient{} = client), do: Repo.delete(client)

  @doc """
  Verifies a `client_id` / `client_secret` pair, returning `{:ok, account}`
  with the owning account preloaded, or `:error`. Runs a constant-time
  verification even on an unknown `client_id` to avoid leaking existence.

  This is the single choke point every self-hosted call (enrollment, usage
  ingestion, token introspection) goes through, so the self-hosted-cache
  entitlement is enforced here too: a downgraded account stops authenticating
  even though its credential still exists.
  """
  def verify(client_id, client_secret) when is_binary(client_id) and is_binary(client_secret) do
    case Repo.one(from(c in SelfHostedClient, where: c.client_id == ^client_id, preload: [:account])) do
      nil ->
        Bcrypt.no_user_verify()
        :error

      %SelfHostedClient{} = client ->
        if Bcrypt.verify_pass(
             client_secret <> Environment.secret_key_password(),
             client.encrypted_secret_hash
           ) and Entitlements.allows?(client.account, :self_hosted_cache) do
          {:ok, client.account}
        else
          :error
        end
    end
  end

  def verify(_client_id, _client_secret), do: :error

  defp generate_client_id do
    @client_id_prefix <> "_" <> random_token(16)
  end

  defp generate_secret, do: random_token(32)

  defp random_token(bytes) do
    bytes
    |> :crypto.strong_rand_bytes()
    |> Base.url_encode64(padding: false)
  end
end
