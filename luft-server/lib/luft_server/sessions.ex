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

  alias LuftServer.AuthEvents
  alias LuftServer.Repo
  alias LuftServer.Sessions.Session
  alias LuftServer.Tuist.OIDC
  alias Plug.Crypto.KeyGenerator

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
      access_token_expires_at: DateTime.shift(now, second: tokens["expires_in"] || 3600),
      expires_at: DateTime.shift(now, day: @session_ttl_days)
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

  @doc "Finds a live session by its ID after authorizing a Luft bearer grant."
  def get_by_id(id) do
    case Ecto.UUID.cast(id) do
      {:ok, id} ->
        Repo.one(from s in Session, where: s.id == ^id and s.expires_at > ^DateTime.utc_now())

      :error ->
        nil
    end
  end

  @doc "Recovers a Boruta refresh response while the owning session is locked."
  def refresh_replay(session, token) do
    with true <- session.previous_token_hash == hash(token),
         %DateTime{} = expires_at <- session.refresh_replay_expires_at,
         :gt <- DateTime.compare(expires_at, DateTime.utc_now()),
         {:ok, response} <- decrypt(session.refresh_response) do
      {:ok, :erlang.binary_to_term(response, [:safe])}
    else
      _ -> :error
    end
  end

  @doc "Stores retry recovery in the transaction that commits Boruta's rotation."
  def remember_refresh(session, token, response) do
    session
    |> Session.changeset(%{
      previous_token_hash: hash(token),
      refresh_response: encrypt(:erlang.term_to_binary(response)),
      refresh_replay_expires_at: DateTime.shift(DateTime.utc_now(:second), minute: 1)
    })
    |> Repo.update!()
  end

  @doc "Reserves a ten-minute native sign-in transaction across replicas."
  def reserve_native_transaction do
    with {:ok, token, session} <-
           create(%{
             claims: %{"sub" => "native-pending"},
             tokens: %{"access_token" => "", "refresh_token" => ""}
           }),
         {:ok, _} <-
           session
           |> Session.changeset(%{
             expires_at: DateTime.shift(DateTime.utc_now(:second), minute: 10)
           })
           |> Repo.update() do
      {:ok, token}
    end
  end

  @doc "Consumes a pending native sign-in, including on failure, exactly once."
  def consume_native_transaction(token) when is_binary(token) do
    {count, _} =
      Repo.delete_all(
        from s in Session,
          where:
            s.token_hash == ^hash(token) and s.user_sub == "native-pending" and
              s.expires_at > ^DateTime.utc_now()
      )

    count == 1
  end

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
      false -> refresh(session)
      :error -> reauthenticate(session)
    end
  end

  defp refresh(%Session{id: session_id} = session) do
    fn ->
      # Refreshes still serialize with each other and logout, but do not need
      # to block execution's key-share locks: only credential columns change.
      session =
        Repo.one(from s in Session, where: s.id == ^session_id, lock: "FOR NO KEY UPDATE") ||
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
                DateTime.shift(DateTime.utc_now(:second), second: tokens["expires_in"] || 3600)
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
    end
    |> Repo.transaction()
    |> case do
      {:ok, access_token} -> {:ok, access_token}
      {:error, :reauthenticate} -> reauthenticate(session)
      {:error, reason} -> {:error, reason}
    end
  end

  defp reauthenticate(session) do
    remove(from s in Session, where: s.id == ^session.id)
    AuthEvents.log(:session_revoked, :reauthenticate, session: session)
    {:error, :reauthenticate}
  end

  @doc "Signs out: deletes the session and revokes Tuist's refresh token."
  def delete(%Session{} = session) do
    # Already gone after a double sign-out or a refused refresh.
    remove(from s in Session, where: s.id == ^session.id)

    with {:ok, refresh_token} <- decrypt(session.refresh_token) do
      OIDC.revoke(refresh_token)
    end

    :ok
  end

  @doc "Deletes expired sessions."
  def prune do
    now = DateTime.utc_now()
    remove(from s in Session, where: s.expires_at <= ^now)
  end

  # Delete sessions first to take the same row locks as native exchanges.
  # Boruta subjects are session UUID strings; its grants have the same retention.
  defp remove(query) do
    Repo.transaction(fn ->
      {count, ids} = Repo.delete_all(from s in query, select: s.id)
      Repo.delete_all(from t in Boruta.Ecto.Token, where: t.sub in ^ids)
      count
    end)
  end

  defp fresh?(%Session{access_token_expires_at: expires_at}) do
    DateTime.after?(
      expires_at,
      DateTime.shift(DateTime.utc_now(), second: @refresh_margin_seconds)
    )
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

    KeyGenerator.generate(secret_key_base, "luft session tokens",
      length: 32,
      cache: Plug.Crypto.Keys
    )
  end
end
