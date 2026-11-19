defmodule LuftServer.Sessions do
  @moduledoc """
  Server-side sessions for people signed in with Tuist. The browser holds only
  an opaque random token in an `HttpOnly`, `Secure`, `SameSite=Strict` cookie;
  Tuist's access and refresh tokens stay here, encrypted at rest (AES-256-GCM
  with a key derived from `SECRET_KEY_BASE`), and never reach the browser.

  Sessions live in PostgreSQL so every replica sees the same ones. A refresh
  rotates Tuist's refresh token, so it runs under a row lock: two replicas
  refreshing the same session at once would otherwise spend the same refresh
  token twice and sign the person out.
  """

  import Ecto.Query

  alias LuftServer.Repo
  alias LuftServer.Sessions.Session
  alias LuftServer.Tuist.OIDC

  @session_ttl_days 30
  # Refresh a little before Tuist's access token expires.
  @refresh_margin_seconds 60

  @doc """
  Creates a session from a completed sign-in. Returns `{:ok, token, session}`,
  where `token` goes in the cookie.
  """
  def create(%{claims: claims, tokens: tokens}) do
    token = 32 |> :crypto.strong_rand_bytes() |> Base.url_encode64(padding: false)
    now = DateTime.utc_now(:second)

    attrs = %{
      token_hash: hash(token),
      user_sub: claims["sub"],
      email: claims["email"],
      handle: claims["preferred_username"],
      access_token: encrypt(tokens["access_token"]),
      refresh_token: encrypt(tokens["refresh_token"]),
      access_token_expires_at: DateTime.add(now, tokens["expires_in"] || 3600, :second),
      expires_at: DateTime.add(now, @session_ttl_days, :day)
    }

    # Sign-ins are rare enough to sweep expired sessions on, without a scheduler.
    prune()

    with {:ok, session} <- %Session{} |> Session.changeset(attrs) |> Repo.insert() do
      {:ok, token, session}
    end
  end

  @doc "The unexpired session for a cookie token, or `nil`."
  def get(token) when is_binary(token) do
    now = DateTime.utc_now()
    Repo.one(from s in Session, where: s.token_hash == ^hash(token) and s.expires_at > ^now)
  end

  def get(_token), do: nil

  @doc """
  A valid Tuist access token for `session`, refreshing it first when it is
  about to expire. `{:error, :reauthenticate}` means Tuist refused the refresh
  token, or the tokens no longer decrypt (`SECRET_KEY_BASE` changed), and the
  person must sign in again; the session is deleted.
  """
  def access_token(%Session{} = session) do
    with true <- fresh?(session),
         {:ok, access_token} <- decrypt(session.access_token) do
      {:ok, access_token}
    else
      false -> refresh(session.id)
      :error -> reauthenticate(session.id)
    end
  end

  defp refresh(session_id) do
    Repo.transaction(fn ->
      session =
        Repo.one(from s in Session, where: s.id == ^session_id, lock: "FOR UPDATE") ||
          Repo.rollback(:reauthenticate)

      # Another request refreshed it while this one waited for the lock.
      with false <- fresh?(session),
           {:ok, refresh_token} <- decrypt(session.refresh_token) do
        case OIDC.refresh(refresh_token) do
          {:ok, tokens} ->
            session
            |> Session.changeset(%{
              access_token: encrypt(tokens["access_token"]),
              refresh_token: encrypt(tokens["refresh_token"] || refresh_token),
              access_token_expires_at:
                DateTime.add(DateTime.utc_now(:second), tokens["expires_in"] || 3600, :second)
            })
            |> Repo.update!()

            tokens["access_token"]

          # Only a refused grant ends the session (RFC 6749, 5.2). Any other
          # error, such as `invalid_client` while the client secret is being
          # rotated on both sides, is Tuist's or ours, and passes.
          {:error, {:oauth, "invalid_grant"}} ->
            Repo.rollback(:reauthenticate)

          {:error, _reason} ->
            Repo.rollback(:provider_unavailable)
        end
      else
        true ->
          case decrypt(session.access_token) do
            {:ok, access_token} -> access_token
            :error -> Repo.rollback(:reauthenticate)
          end

        :error ->
          Repo.rollback(:reauthenticate)
      end
    end)
    |> case do
      {:ok, access_token} -> {:ok, access_token}
      {:error, :reauthenticate} -> reauthenticate(session_id)
      {:error, reason} -> {:error, reason}
    end
  end

  defp reauthenticate(session_id) do
    Repo.delete_all(from s in Session, where: s.id == ^session_id)
    {:error, :reauthenticate}
  end

  @doc "Signs out: deletes the session and revokes Tuist's refresh token."
  def delete(%Session{} = session) do
    # Already gone after a double sign-out or a refused refresh.
    Repo.delete_all(from s in Session, where: s.id == ^session.id)

    with {:ok, refresh_token} <- decrypt(session.refresh_token) do
      OIDC.revoke(refresh_token)
    end

    :ok
  end

  @doc "Deletes expired sessions."
  def prune do
    now = DateTime.utc_now()
    Repo.delete_all(from s in Session, where: s.expires_at <= ^now)
  end

  defp fresh?(%Session{access_token_expires_at: expires_at}) do
    DateTime.compare(
      expires_at,
      DateTime.add(DateTime.utc_now(), @refresh_margin_seconds, :second)
    ) == :gt
  end

  defp hash(token), do: :crypto.hash(:sha256, token)

  defp encrypt(plaintext) when is_binary(plaintext) do
    iv = :crypto.strong_rand_bytes(12)

    {ciphertext, tag} =
      :crypto.crypto_one_time_aead(:aes_256_gcm, key(), iv, plaintext, "luft-session", true)

    iv <> tag <> ciphertext
  end

  defp decrypt(<<iv::binary-12, tag::binary-16, ciphertext::binary>>) do
    case :crypto.crypto_one_time_aead(
           :aes_256_gcm,
           key(),
           iv,
           ciphertext,
           "luft-session",
           tag,
           false
         ) do
      plaintext when is_binary(plaintext) -> {:ok, plaintext}
      :error -> :error
    end
  end

  defp decrypt(_value), do: :error

  defp key do
    secret_key_base =
      Application.fetch_env!(:luft_server, LuftServerWeb.Endpoint)[:secret_key_base]

    Plug.Crypto.KeyGenerator.generate(secret_key_base, "luft session tokens",
      length: 32,
      cache: Plug.Crypto.Keys
    )
  end
end
