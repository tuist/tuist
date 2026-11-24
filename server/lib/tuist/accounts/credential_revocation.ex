defmodule Tuist.Accounts.CredentialRevocation do
  @moduledoc """
  Revokes customer-facing credentials in bulk, for an incident where they may
  have leaked: browser sessions and pending sign-in links, CLI and app refresh
  tokens, OAuth grants, device codes, agent credentials, account tokens
  (including SCIM) and project tokens.
  Run it through `Tuist.Release.revoke_credentials/1`, following the runbook in
  `server/docs/credential-revocation.md`.

  Access tokens are signed and not stored, so `users.credentials_revoked_at`
  and `accounts.credentials_revoked_at` reject every one issued at or before
  the revocation. Two things are not covered: cache JWTs, which cache nodes
  verify on their own until they expire (30 minutes), and the per-node
  authentication caches, which can serve a revoked credential for up to a
  minute. Passwords, passkeys and MFA factors are left alone: they are
  factors, not bearer credentials.

  Revoking one organization account also revokes the user credentials of its
  members, since those act for the organization too; it signs them out of
  their other accounts as well.
  """
  import Ecto.Query

  alias Tuist.Accounts
  alias Tuist.Accounts.Account
  alias Tuist.Accounts.AccountToken
  alias Tuist.Accounts.AgentAuthCredential
  alias Tuist.Accounts.DeviceCode
  alias Tuist.Accounts.User
  alias Tuist.Accounts.UserToken
  alias Tuist.Projects.ProjectToken
  alias Tuist.Repo

  @doc """
  Revokes every customer-facing credential. Each step is idempotent, and they
  are not wrapped in one transaction, so a rerun finishes an interrupted run.
  Returns the number of rows each step touched.
  """
  def revoke_everything do
    now = now()
    session_tokens = Repo.all(from(t in UserToken, where: t.context == "session", select: t.token))

    counts = %{
      accounts: count(Repo.update_all(from(a in Account), set: [credentials_revoked_at: now])),
      users: count(Repo.update_all(from(u in "users"), set: [credentials_revoked_at: now])),
      browser_tokens: count(Repo.delete_all(UserToken)),
      refresh_tokens: count(Repo.delete_all("guardian_tokens")),
      oauth_tokens: count(Repo.update_all(unrevoked_oauth_tokens(), set: oauth_revocation(now))),
      device_codes: count(Repo.delete_all(DeviceCode)),
      agent_credentials:
        count(Repo.update_all(from(c in AgentAuthCredential, where: is_nil(c.revoked_at)), set: [revoked_at: now])),
      account_tokens: count(Repo.delete_all(AccountToken)),
      project_tokens: count(Repo.delete_all(ProjectToken))
    }

    disconnect(session_tokens)
    counts
  end

  @doc """
  Revokes the credentials of one account: its account and project tokens and its account JWTs, plus the user credentials of its owner
  or, for an organization, of its members.
  """
  def revoke_account(account_id) do
    case Repo.get(Account, account_id) do
      nil -> {:error, :not_found}
      account -> revoke_account(account, users(account))
    end
  end

  defp revoke_account(%Account{id: account_id}, users) do
    now = now()
    project_ids = from(p in "projects", where: p.account_id == ^account_id, select: p.id)

    {:ok, {counts, session_tokens}} =
      Repo.transaction(fn ->
        Repo.update_all(from(a in Account, where: a.id == ^account_id), set: [credentials_revoked_at: now])

        session_tokens = Enum.flat_map(users, &revoke_user/1)

        counts = %{
          users: length(users),
          account_tokens: count(Repo.delete_all(from(t in AccountToken, where: t.account_id == ^account_id))),
          project_tokens: count(Repo.delete_all(from(t in ProjectToken, where: t.project_id in subquery(project_ids))))
        }

        {counts, session_tokens}
      end)

    disconnect(session_tokens)
    {:ok, counts}
  end

  # The same revocation a password reset performs, under the user row lock
  # `Accounts.revoke_user_api_credentials/1` expects.
  defp revoke_user(%User{id: id} = user) do
    Repo.one!(from(u in User, where: u.id == ^id, lock: "FOR UPDATE", select: u.id))
    session_tokens = Repo.all(from(t in UserToken, where: t.user_id == ^id and t.context == "session", select: t.token))
    Repo.delete_all(UserToken.by_user_and_contexts_query(user, :all))
    :ok = Accounts.revoke_user_api_credentials(user)
    session_tokens
  end

  defp users(%Account{user_id: user_id}) when not is_nil(user_id), do: [Repo.get!(User, user_id)]

  defp users(%Account{} = account) do
    organization = account |> Repo.preload(:organization) |> Map.fetch!(:organization)

    [:admin, :user, :viewer]
    |> Enum.flat_map(&Accounts.get_organization_members(organization, &1))
    |> Enum.uniq_by(& &1.id)
  end

  defp unrevoked_oauth_tokens do
    from(t in Boruta.Ecto.Token, where: is_nil(t.revoked_at) or is_nil(t.refresh_token_revoked_at))
  end

  defp oauth_revocation(now), do: [revoked_at: now, refresh_token_revoked_at: now]

  # A connected LiveView keeps its user in assigns and never looks the session
  # up again, so deleting the rows alone leaves it working. Published to the
  # shared pubsub, as `Tuist.Accounts.Dormancy` does, because a `Tuist` module
  # may not reference `TuistWeb`.
  defp disconnect(session_tokens) do
    Enum.each(session_tokens, fn token ->
      topic = UserToken.live_socket_id(token)

      Phoenix.PubSub.broadcast(Tuist.PubSub, topic, %Phoenix.Socket.Broadcast{
        topic: topic,
        event: "disconnect",
        payload: %{}
      })
    end)
  end

  defp count({count, _}), do: count
  defp now, do: DateTime.truncate(DateTime.utc_now(), :second)
end
