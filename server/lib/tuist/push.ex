defmodule Tuist.Push do
  @moduledoc """
  Associates native app installations (and their push tokens) with users.
  Which notifications a user wants is up to `Tuist.Notifications`; this module
  only knows which of their devices can receive them.

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
  - A row never changes owner, and a device token is live in one row only.
    Registering a token retires every other live row that holds it
    (`superseded`, or `owner_changed` when another user's row has the same
    installation ID), so one user's notifications never reach a device that
    someone else has signed into since. Another user's installation ID with a
    different token is a `:conflict`.
  - Users keep at most ten live rows; the oldest are `evicted`.
  - `removed` tombstones are never pruned, so a removed device stays off even
    if its app comes back after a long time.

  Every server, hosted or on-premise, owns the registrations of the users who
  sign into it. Only tuist.dev holds the APNs key and FCM credentials for the
  Tuist apps, so delivery from on-premise servers must relay through tuist.dev
  (license-authenticated, token plus content-free payload) rather than call the
  providers directly.
  """

  import Ecto.Query

  alias Tuist.Accounts.User
  alias Tuist.Environment
  alias Tuist.MCP.Events.OAuthGrants
  alias Tuist.OAuth.Clients
  alias Tuist.Push.Installation
  alias Tuist.Repo

  @max_live_per_user 10
  @stale_after_days 60
  @tombstone_retention_days 180
  @prune_batch_size 1000
  @uuid ~r/\A[0-9a-f]{8}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{12}\z/
  @apns_token ~r/\A(?:[0-9a-fA-F]{2}){16,256}\z/
  @android_token ~r/\A[\x21-\x7E]{16,4096}\z/
  @max_device_name_length 64

  @doc """
  Resolves the OAuth grant behind `bearer` for `user`. Only sign-ins through the
  Tuist app client (`Tuist.Environment.oauth_client_id/0`) with a refresh token
  qualify; dynamically registered OAuth clients, account tokens and other
  credentials return `{:error, :oauth_session_required}`.
  """
  def oauth_session(bearer, %User{id: user_id}) when is_binary(bearer) do
    client_id = Environment.oauth_client_id()

    with {:ok, %{"client_id" => ^client_id, "user_id" => ^user_id}} when is_binary(client_id) <-
           Tuist.Guardian.decode_and_verify(bearer),
         %Boruta.Ecto.Token{} = grant <- OAuthGrants.find_bearer(bearer, client_id, user_id),
         {:ok, grant_id} <- OAuthGrants.root_id(grant) do
      {:ok, %{oauth_grant_id: grant_id}}
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
  Removes one of `user`'s devices by its server registration ID, from the app's
  device list or the dashboard. Unlike `unregister/2`, the app keeps it off when
  it next tries to refresh its registration (`:removed`). Always `:ok`.
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

  def prune_batch_size, do: @prune_batch_size

  @doc """
  Retires up to #{@prune_batch_size} registrations the app has not refreshed for
  #{@stale_after_days} days (clients re-register on foreground) and deletes up to
  #{@prune_batch_size} tombstones older than #{@tombstone_retention_days} days,
  except `removed` ones.
  """
  def prune do
    now = now()

    stale =
      Installation
      |> where([i], is_nil(i.retired_at) and i.last_registered_at < ^DateTime.add(now, -@stale_after_days, :day))
      |> limit(@prune_batch_size)
      |> select([i], i.id)

    {retired, _} =
      Installation
      |> where([i], i.id in subquery(stale) and is_nil(i.retired_at))
      |> Repo.update_all(set: retired_fields("stale"))

    expired =
      Installation
      |> where([i], i.retired_at < ^DateTime.add(now, -@tombstone_retention_days, :day))
      |> where([i], i.retired_reason != "removed")
      |> limit(@prune_batch_size)
      |> select([i], i.id)

    {deleted, _} = Installation |> where([i], i.id in subquery(expired)) |> Repo.delete_all()

    %{retired: retired, deleted: deleted}
  end

  # Raises on database errors, so a transient failure never retires a live device.
  defp session_active?(%Installation{oauth_grant_id: grant_id, user_id: user_id}) do
    ttl = Clients.public!().refresh_token_ttl
    match?({:ok, _scope}, OAuthGrants.active_scope(grant_id, Environment.oauth_client_id(), user_id, ttl))
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
        # The installation lock does not serialize a user's other installations,
        # so take a per-user lock before enforcing the cap. The order is always
        # installation, then user.
        Repo.query!("SELECT pg_advisory_xact_lock(hashtextextended($1, 0))", ["push_user:#{user.id}"])
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
    [
      retired_at: now(),
      retired_reason: reason,
      user_id: nil,
      oauth_grant_id: nil,
      device_name: nil,
      token: nil,
      token_hash: nil
    ]
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
