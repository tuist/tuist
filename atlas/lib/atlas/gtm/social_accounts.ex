defmodule Atlas.GTM.SocialAccounts do
  @moduledoc """
  Social accounts held by Atlas for post tracking. Anyone with `gtm:write` can
  connect or disconnect one; the grant stays with the account, not with that
  person. Tokens are only read by `with_token/2` for the sync and are never
  returned by a LiveView or MCP tool.
  """

  import Ecto.Query

  alias Atlas.Audit
  alias Atlas.Connections.Provider
  alias Atlas.GTM.LinkedIn
  alias Atlas.GTM.SocialAccount
  alias Atlas.Repo
  alias Atlas.Users
  alias Atlas.Users.User

  @dashboard_path "/commercial/gtm/social/performance"

  def list do
    SocialAccount
    |> order_by([a], asc: a.kind, asc: a.handle)
    |> preload(:connected_by)
    |> Repo.all()
  end

  def can_manage?(user), do: Users.has_scope?(user, "gtm:write")

  @doc """
  Exchanges an authorization code and stores the account it belongs to: the
  signed-in X account, or the LinkedIn Page the signed-in member administers.
  LinkedIn Pages are always brand accounts.
  """
  def connect(%User{} = user, platform, kind, code, redirect_uri, verifier) do
    with :ok <- authorize(user),
         true <- platform in SocialAccount.platforms() || {:error, :invalid_platform},
         true <- kind in SocialAccount.kinds() || {:error, :invalid_kind},
         true <- (platform == "x" or kind == "brand") || {:error, :invalid_kind},
         {:ok, attrs} <- Provider.exchange(platform, code, redirect_uri, verifier),
         {:ok, attrs} <- identify(platform, attrs),
         {:ok, account} <- save(user, platform, kind, attrs) do
      audit("social_account.connected", account, user)
      {:ok, account}
    end
  end

  defp identify("x", attrs),
    do: {:ok, Map.merge(attrs, %{external_id: attrs.provider_user_id, handle: attrs.account_name})}

  defp identify("linkedin", attrs) do
    with {:ok, %{id: id, name: name}} <- LinkedIn.administered_page(attrs.access_token) do
      {:ok, Map.merge(attrs, %{external_id: id, handle: name})}
    end
  end

  @doc "Removes the account's grant. Its posts and their history stay."
  def disconnect(%User{} = user, id) do
    with :ok <- authorize(user) do
      Repo.transaction(fn ->
        case Repo.one(from a in SocialAccount, where: a.id == ^id, lock: "FOR UPDATE") do
          nil ->
            Repo.rollback(:not_found)

          account ->
            Repo.delete!(account)
            audit("social_account.disconnected", account, user)
            account
        end
      end)
    end
  end

  def mark_synced(%SocialAccount{} = account) do
    account
    |> Ecto.Changeset.change(last_synced_at: DateTime.utc_now() |> DateTime.truncate(:second))
    |> Repo.update!()
  end

  @doc """
  Calls `fun` with a current access token, refreshing it when it expired or X
  rejected it. Refreshes lock the row, because X rotates refresh tokens.
  """
  def with_token(%SocialAccount{} = account, fun) do
    with {:ok, token} <- token(account, nil) do
      case fun.(token) do
        {:error, {:http, 401, _detail}} -> with {:ok, refreshed} <- token(account, token), do: fun.(refreshed)
        result -> result
      end
    end
  end

  defp token(account, rejected) do
    account
    |> locked_token(rejected)
    |> case do
      {:ok, :needs_authorization} -> {:error, :needs_authorization}
      result -> result
    end
  end

  defp locked_token(account, rejected) do
    Repo.transaction(fn ->
      locked = Repo.one(from a in SocialAccount, where: a.id == ^account.id, lock: "FOR UPDATE")

      cond do
        is_nil(locked) -> Repo.rollback(:not_connected)
        locked.needs_authorization -> Repo.rollback(:needs_authorization)
        SocialAccount.expired?(locked) or locked.access_token == rejected -> refresh(locked)
        true -> locked.access_token
      end
    end)
  end

  defp refresh(%SocialAccount{refresh_token: nil} = account), do: needs_authorization(account)

  defp refresh(account) do
    case Provider.refresh(account.platform, account.refresh_token) do
      {:ok, attrs} ->
        attrs = Map.update!(attrs, :refresh_token, &(&1 || account.refresh_token))
        attrs = if attrs.scopes == [], do: Map.put(attrs, :scopes, account.scopes), else: attrs
        account |> SocialAccount.changeset(attrs) |> Repo.update!() |> Map.fetch!(:access_token)

      {:error, :needs_authorization} ->
        needs_authorization(account)

      {:error, reason} ->
        Repo.rollback(reason)
    end
  end

  # Commits with the transaction, so a revoked grant shows as needing a reconnect.
  defp needs_authorization(account) do
    account |> Ecto.Changeset.change(needs_authorization: true) |> Repo.update!()
    audit("social_account.needs_authorization", account, nil)
    :needs_authorization
  end

  defp save(user, platform, kind, attrs) do
    Repo.transaction(fn ->
      existing =
        Repo.one(
          from a in SocialAccount,
            where: a.platform == ^platform and a.external_id == ^attrs.external_id,
            lock: "FOR UPDATE"
        )

      attrs =
        attrs
        |> Map.put(:kind, kind)
        |> Map.update!(:refresh_token, &(&1 || (existing && existing.refresh_token)))

      (existing || %SocialAccount{platform: platform, external_id: attrs.external_id})
      |> SocialAccount.changeset(attrs)
      |> Ecto.Changeset.put_change(:connected_by_id, user.id)
      |> Repo.insert_or_update()
      |> case do
        {:ok, account} -> account
        {:error, changeset} -> Repo.rollback(changeset)
      end
    end)
  end

  defp authorize(user), do: if(can_manage?(user), do: :ok, else: {:error, :forbidden})

  defp audit(action, account, user) do
    Audit.record(
      action,
      %{
        target_type: "social_account",
        target_id: account.id,
        target_label: account.handle,
        metadata: %{"platform" => account.platform, "kind" => account.kind, "dashboard_path" => @dashboard_path}
      },
      if(user, do: [actor: user], else: [])
    )
  end
end
