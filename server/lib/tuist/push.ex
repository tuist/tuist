defmodule Tuist.Push do
  @moduledoc """
  Associates native app installations (and their push tokens) with users.

  Ported from Atlas's `Atlas.Push` registry, with one difference: hosted Tuist
  apps share a single OAuth client, so a registration is bound to the user's
  OAuth grant (the refresh-token lineage of one sign-in) rather than to the
  client. A registration is only usable while that grant is active, which makes
  sign-out, revocation and refresh expiry end it without a client round trip.

  - `push_installations` is keyed by the client-generated `installation_id`
    (lowercase UUID). Tokens are encrypted with `Tuist.Vault`; `token_hash`
    enforces one live owner per device token.
  - Retired rows are tombstones: owner, grant and token cleared, installation ID
    kept, and any later registration of that ID returns `:retired`. Clients
    rotate their installation ID after a successful unregister or `:retired`.
  - Ownership never moves between users. Another user's live row is retired
    (`owner_changed`) only when the caller presents the same device token, which
    proves it is the same app installation; otherwise `:conflict`.
  - Users keep at most ten live rows; the oldest are `evicted`.

  Every server, hosted or on-premise, owns the registrations of the users who
  sign into it. Only tuist.dev holds the APNs key and FCM credentials for the
  Tuist apps, so delivery from on-premise servers must relay through tuist.dev
  (license-authenticated, token plus content-free payload) rather than call the
  providers directly.
  """

  import Ecto.Query

  alias Tuist.Accounts
  alias Tuist.Accounts.User
  alias Tuist.MCP.Events.OAuthGrants
  alias Tuist.OAuth.Clients
  alias Tuist.Projects
  alias Tuist.Projects.Project
  alias Tuist.Push.Installation
  alias Tuist.Push.Preference
  alias Tuist.Push.ProjectPreference
  alias Tuist.Repo

  @max_live_per_user 10
  @stale_after_days 60
  @tombstone_retention_days 180
  @uuid ~r/\A[0-9a-f]{8}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{12}\z/
  @apns_token ~r/\A(?:[0-9a-fA-F]{2}){16,256}\z/
  @android_token ~r/\A[\x21-\x7E]{16,4096}\z/
  @max_device_name_length 64
  @preference_kinds ["new_preview"]

  def preference_kinds, do: @preference_kinds

  @doc """
  Resolves the OAuth grant behind `bearer` for `user`. Only OAuth sessions with a
  refresh token (the native apps' PKCE sign-in) qualify; account tokens and other
  credentials return `{:error, :oauth_session_required}`.
  """
  def oauth_session(bearer, %User{id: user_id}) when is_binary(bearer) do
    with {:ok, %{"client_id" => client_id, "user_id" => ^user_id}} <- Tuist.Guardian.decode_and_verify(bearer),
         {:ok, client_id} <- Ecto.UUID.cast(client_id),
         %Boruta.Ecto.Token{} = grant <- OAuthGrants.find_bearer(bearer, client_id, user_id),
         {:ok, grant_id} <- OAuthGrants.root_id(grant) do
      {:ok, %{oauth_client_id: client_id, oauth_grant_id: grant_id}}
    else
      _ -> {:error, :oauth_session_required}
    end
  end

  @doc """
  Registers or refreshes `installation_id` for `user` under `session` (from
  `oauth_session/2`). `device` has `:platform` (`ios` or `android`), `:token`
  and `:environment` (`sandbox` or `production`; Android is always
  `production`), plus an optional `:name` the user sees in their device list
  (the device model).

  Returns `{:ok, installation}` or `{:error, reason}` where reason is
  `:invalid`, `:retired` (the client must rotate to a new UUID), `:removed`
  (the user removed this device from their device list; the client must not
  re-register until the user turns notifications back on, then rotates), or
  `:conflict` (another user's live installation).
  """
  def register(%User{} = user, session, installation_id, device) do
    with {:ok, installation_id} <- validate_installation_id(installation_id),
         {:ok, attrs} <- validate_device(device) do
      token_hash = Installation.token_hash(attrs.platform, attrs.token)

      installation_id
      |> locked(&upsert(&1, user, session, installation_id, attrs, token_hash))
      |> case do
        {:ok, result} -> result
        {:error, %Ecto.Changeset{}} -> {:error, :conflict}
      end
    end
  end

  @doc """
  Retires `installation_id` when it belongs to `user`. Unknown IDs become
  tombstones so a registration that arrives after its deletion is rejected.
  Other users' installations are left untouched. Always `:ok` for a valid ID.
  """
  def unregister(%User{} = user, installation_id) do
    with {:ok, installation_id} <- validate_installation_id(installation_id) do
      {:ok, :ok} =
        locked(installation_id, fn
          nil ->
            Repo.insert!(%Installation{
              installation_id: installation_id,
              retired_at: now(),
              retired_reason: "unregistered"
            })

            :ok

          %Installation{retired_at: nil, user_id: user_id} = installation when user_id == user.id ->
            retire!(installation, "unregistered")
            :ok

          %Installation{} ->
            :ok
        end)

      :ok
    end
  end

  @doc """
  Removes one of `user`'s devices by its server registration ID, for example
  from the dashboard. Unlike `unregister/2`, the app keeps it off when it next
  tries to refresh its registration (`:removed`). Always `:ok`.
  """
  def remove_device(%User{id: user_id}, registration_id) do
    with {:ok, registration_id} <- Ecto.UUID.cast(registration_id),
         %Installation{installation_id: installation_id} <-
           Repo.get_by(Installation, id: registration_id, user_id: user_id) do
      {:ok, _} =
        locked(installation_id, fn
          %Installation{retired_at: nil, user_id: ^user_id} = installation -> retire!(installation, "removed")
          _ -> :ok
        end)
    end

    :ok
  end

  @doc """
  The user's live installations whose OAuth grant is still active. Installations
  whose sign-in has ended are retired as `session_ended` instead of returned.
  This is the set a future delivery fan-out should target.
  """
  def live_installations(user_id) do
    Installation
    |> where([i], i.user_id == ^user_id and is_nil(i.retired_at))
    |> order_by([i], desc: i.last_registered_at)
    |> Repo.all()
    |> Enum.filter(fn installation ->
      session_active?(installation) or retire_session_ended(installation)
    end)
  end

  @doc """
  `user`'s own `kind` choices for every account (their personal account and
  their organizations) that owns a project they can access, sorted by name:

      [%{account: account, enabled: boolean,
         projects: [%{project: project, override: nil | boolean, enabled: boolean}]}]

  An account is enabled unless the user turned it off. A project's `override`
  is nil when it follows its account; `enabled` is the effective choice.
  """
  def preferences(%User{id: user_id} = user, kind) when kind in @preference_kinds do
    account_choices =
      Preference
      |> where([p], p.user_id == ^user_id and p.kind == ^kind)
      |> select([p], {p.account_id, p.enabled})
      |> Repo.all()
      |> Map.new()

    overrides =
      ProjectPreference
      |> where([p], p.user_id == ^user_id and p.kind == ^kind)
      |> select([p], {p.project_id, p.enabled})
      |> Repo.all()
      |> Map.new()

    user
    |> Projects.list_accessible_projects(preload: [:account])
    |> Enum.group_by(& &1.account_id)
    |> Enum.map(fn {account_id, [%{account: account} | _] = projects} ->
      enabled = Map.get(account_choices, account_id, true)

      %{
        account: account,
        enabled: enabled,
        projects:
          projects
          |> Enum.sort_by(& &1.name)
          |> Enum.map(fn project ->
            override = Map.get(overrides, project.id)
            %{project: project, override: override, enabled: if(is_nil(override), do: enabled, else: override)}
          end)
      }
    end)
    |> Enum.sort_by(& &1.account.name)
  end

  @doc """
  `user`'s `kind` choice for one project, as
  `%{override: nil | boolean, account_enabled: boolean, enabled: boolean}`,
  or nil when the project is outside the user's accounts (for example a public
  project they only browse).
  """
  def project_preference(%User{id: user_id} = user, kind, %Project{id: project_id, account_id: account_id})
      when kind in @preference_kinds do
    if account_id in accessible_account_ids(user) do
      override =
        ProjectPreference
        |> where([p], p.user_id == ^user_id and p.project_id == ^project_id and p.kind == ^kind)
        |> select([p], p.enabled)
        |> Repo.one()

      account_enabled =
        Preference
        |> where([p], p.user_id == ^user_id and p.account_id == ^account_id and p.kind == ^kind)
        |> select([p], p.enabled)
        |> Repo.one()
        |> Kernel.!=(false)

      %{
        override: override,
        account_enabled: account_enabled,
        enabled: if(is_nil(override), do: account_enabled, else: override)
      }
    end
  end

  def project_preference(_user, _kind, _project), do: nil

  @doc """
  Turns `kind` on or off for the projects of `account_id`, which must be the
  user's personal account or one of their organizations. Project overrides
  are kept. Returns `:ok` or `{:error, :invalid}`.
  """
  def update_account_preference(%User{id: user_id} = user, kind, account_id, enabled)
      when kind in @preference_kinds and is_integer(account_id) and is_boolean(enabled) do
    if account_id in accessible_account_ids(user) do
      Repo.insert!(%Preference{user_id: user_id, account_id: account_id, kind: kind, enabled: enabled},
        on_conflict: [set: [enabled: enabled, updated_at: now()]],
        conflict_target: [:user_id, :account_id, :kind]
      )

      :ok
    else
      {:error, :invalid}
    end
  end

  def update_account_preference(_user, _kind, _account_id, _enabled), do: {:error, :invalid}

  @doc """
  Overrides `kind` for one project the user can access: `true` or `false`, or
  `nil` to follow the project's account again. Returns `:ok` or
  `{:error, :invalid}`.
  """
  def update_project_preference(%User{id: user_id} = user, kind, project_id, override)
      when kind in @preference_kinds and is_integer(project_id) and (is_boolean(override) or is_nil(override)) do
    case Repo.get(Project, project_id) do
      %Project{account_id: account_id} ->
        if account_id in accessible_account_ids(user) do
          save_project_override(user_id, kind, project_id, override)
        else
          {:error, :invalid}
        end

      nil ->
        {:error, :invalid}
    end
  end

  def update_project_preference(_user, _kind, _project_id, _override), do: {:error, :invalid}

  defp save_project_override(user_id, kind, project_id, nil) do
    ProjectPreference
    |> where([p], p.user_id == ^user_id and p.project_id == ^project_id and p.kind == ^kind)
    |> Repo.delete_all()

    :ok
  end

  defp save_project_override(user_id, kind, project_id, enabled) do
    Repo.insert!(%ProjectPreference{user_id: user_id, project_id: project_id, kind: kind, enabled: enabled},
      on_conflict: [set: [enabled: enabled, updated_at: now()]],
      conflict_target: [:user_id, :project_id, :kind]
    )

    :ok
  end

  defp accessible_account_ids(user) do
    [Accounts.get_account_from_user(user).id | Enum.map(Accounts.get_user_organization_accounts(user), & &1.account.id)]
  end

  @doc """
  Whether `user_id` wants `kind` notifications about `project_id`: their
  project override, else their choice for the project's account, else yes.
  Callers still have to check that the user can access the project at send time.
  """
  def notify?(user_id, kind, project_id) when kind in @preference_kinds do
    Project
    |> where([p], p.id == ^project_id)
    |> join(:left, [p], o in ProjectPreference, on: o.project_id == p.id and o.user_id == ^user_id and o.kind == ^kind)
    |> join(:left, [p], a in Preference, on: a.account_id == p.account_id and a.user_id == ^user_id and a.kind == ^kind)
    |> select([_p, o, a], coalesce(o.enabled, coalesce(a.enabled, true)))
    |> Repo.one()
    |> Kernel.==(true)
  end

  @doc """
  Retires registrations the app has not refreshed for #{@stale_after_days} days
  (clients re-register on foreground) and deletes tombstones after
  #{@tombstone_retention_days} days.
  """
  def prune do
    now = now()

    {stale, _} =
      Installation
      |> where([i], is_nil(i.retired_at) and i.last_registered_at < ^DateTime.add(now, -@stale_after_days, :day))
      |> Repo.update_all(set: retired_fields("stale"))

    {deleted, _} =
      Installation
      |> where([i], i.retired_at < ^DateTime.add(now, -@tombstone_retention_days, :day))
      |> Repo.delete_all()

    {:ok, %{retired: stale, deleted: deleted}}
  end

  defp session_active?(%Installation{} = installation) do
    case Clients.get_client(installation.oauth_client_id) do
      %{refresh_token_ttl: ttl} when is_integer(ttl) ->
        match?(
          {:ok, _scope},
          OAuthGrants.active_scope(installation.oauth_grant_id, installation.oauth_client_id, installation.user_id, ttl)
        )

      _ ->
        false
    end
  end

  # Compare-and-retire on the grant, so a concurrent re-registration that
  # rebound the row to a new sign-in survives.
  defp retire_session_ended(%Installation{} = installation) do
    Installation
    |> where(
      [i],
      i.id == ^installation.id and i.oauth_grant_id == ^installation.oauth_grant_id and is_nil(i.retired_at)
    )
    |> Repo.update_all(set: retired_fields("session_ended"))

    false
  end

  # A transaction-scoped advisory lock serializes concurrent requests for the
  # same installation, including its very first insert.
  defp locked(installation_id, fun) do
    Repo.transaction(fn ->
      Repo.query!("SELECT pg_advisory_xact_lock(hashtextextended($1, 0))", ["push_installation:" <> installation_id])

      Installation
      |> where([i], i.installation_id == ^installation_id)
      |> lock("FOR UPDATE")
      |> Repo.one()
      |> fun.()
    end)
  end

  defp upsert(%Installation{retired_reason: "removed"}, _user, _session, _installation_id, _attrs, _hash),
    do: {:error, :removed}

  defp upsert(%Installation{retired_at: %DateTime{}}, _user, _session, _installation_id, _attrs, _hash),
    do: {:error, :retired}

  defp upsert(%Installation{platform: platform}, _user, _session, _installation_id, %{platform: other}, _hash)
       when platform != other, do: {:error, :conflict}

  defp upsert(%Installation{user_id: user_id} = existing, %User{id: user_id} = user, session, _id, attrs, hash),
    do: save(existing, user, session, attrs, hash)

  defp upsert(%Installation{} = existing, _user, _session, _installation_id, _attrs, hash) do
    # Ownership never moves between users. When the same app installation proves
    # itself with the same device token (for example, a sign-out that could not
    # reach the server followed by another user's sign-in), retire the previous
    # owner's row and make the client rotate.
    if existing.token_hash == hash do
      retire!(existing, "owner_changed")
      {:error, :retired}
    else
      {:error, :conflict}
    end
  end

  defp upsert(nil, user, session, installation_id, attrs, hash),
    do: save(%Installation{installation_id: installation_id}, user, session, attrs, hash)

  defp save(installation, user, session, attrs, hash) do
    now = now()

    # The same device token under another installation ID (reinstall or restore)
    # is one physical device: only the newest registration may own it.
    Installation
    |> where([i], i.token_hash == ^hash and is_nil(i.retired_at))
    |> where([i], i.installation_id != ^installation.installation_id)
    |> Repo.update_all(set: retired_fields("superseded"))

    installation
    |> Ecto.Changeset.change(%{
      user_id: user.id,
      oauth_client_id: session.oauth_client_id,
      oauth_grant_id: session.oauth_grant_id,
      platform: attrs.platform,
      device_name: attrs.name,
      environment: attrs.environment,
      token: attrs.token,
      token_hash: hash,
      token_updated_at: if(installation.token_hash == hash, do: installation.token_updated_at, else: now),
      last_registered_at: now
    })
    |> Ecto.Changeset.unique_constraint(:installation_id)
    |> Ecto.Changeset.unique_constraint(:token_hash, name: :push_installations_live_token_hash_index)
    |> Repo.insert_or_update()
    |> case do
      {:ok, saved} ->
        evict_oldest!(user.id)
        {:ok, saved}

      {:error, changeset} ->
        Repo.rollback(changeset)
    end
  end

  defp evict_oldest!(user_id) do
    keep =
      Installation
      |> where([i], i.user_id == ^user_id and is_nil(i.retired_at))
      |> order_by([i], desc: i.last_registered_at, desc: i.id)
      |> limit(@max_live_per_user)
      |> select([i], i.id)

    Installation
    |> where([i], i.user_id == ^user_id and is_nil(i.retired_at) and i.id not in subquery(keep))
    |> Repo.update_all(set: retired_fields("evicted"))
  end

  defp retire!(installation, reason) do
    installation
    |> Ecto.Changeset.change(retired_fields(reason))
    |> Repo.update!()
  end

  defp retired_fields(reason) do
    [retired_at: now(), retired_reason: reason, user_id: nil, oauth_grant_id: nil, token: nil, token_hash: nil]
  end

  defp now, do: DateTime.truncate(DateTime.utc_now(), :second)

  defp validate_installation_id(value) when is_binary(value) do
    if Regex.match?(@uuid, value), do: {:ok, value}, else: {:error, :invalid}
  end

  defp validate_installation_id(_value), do: {:error, :invalid}

  defp validate_device(%{platform: platform, token: token, environment: environment} = device)
       when is_binary(platform) and is_binary(token) and is_binary(environment) do
    with {:ok, token} <- validate_token(platform, token),
         true <- valid_environment?(platform, environment),
         {:ok, name} <- validate_device_name(Map.get(device, :name)) do
      {:ok, %{platform: platform, token: token, environment: environment, name: name}}
    else
      _ -> {:error, :invalid}
    end
  end

  defp validate_device(_device), do: {:error, :invalid}

  defp validate_device_name(nil), do: {:ok, nil}

  # Control and format characters are collapsed so a name always renders as one line.
  defp validate_device_name(name) when is_binary(name) do
    if String.valid?(name) do
      name =
        name |> String.replace(~r/[\p{Cc}\p{Cf}\s]+/u, " ") |> String.trim() |> String.slice(0, @max_device_name_length)

      {:ok, if(name == "", do: nil, else: name)}
    else
      :error
    end
  end

  defp validate_device_name(_name), do: :error

  defp validate_token("ios", token) do
    if Regex.match?(@apns_token, token), do: {:ok, String.downcase(token)}, else: :error
  end

  defp validate_token("android", token) do
    if Regex.match?(@android_token, token), do: {:ok, token}, else: :error
  end

  defp validate_token(_platform, _token), do: :error

  defp valid_environment?("ios", environment), do: environment in ["sandbox", "production"]
  defp valid_environment?("android", environment), do: environment == "production"
end
