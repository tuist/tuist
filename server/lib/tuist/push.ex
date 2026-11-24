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

  Two first-party apps register, each through its own fixed OAuth client: the
  Tuist app (`app: "tuist"`, `Tuist.Environment.oauth_client_id/0`) and Tuist
  Luft (`app: "luft"`, `Tuist.OAuth.Clients.luft_client_id/0`). The configured
  Luft server may also register Luft installations with a `luft:app` grant.
  Each app only receives its own
  notifications (previews for the Tuist app, finished threads for Luft), on its
  own APNs topic; Luft's macOS app registers as the `macos` platform.

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

  alias Boruta.Ecto.Token
  alias Boruta.Oauth.Client
  alias Tuist.Accounts.User
  alias Tuist.Environment
  alias Tuist.MCP.Events.OAuthGrants
  alias Tuist.OAuth.Clients
  alias Tuist.Push.APNs
  alias Tuist.Push.FCM
  alias Tuist.Push.Installation
  alias Tuist.Push.LiveActivities
  alias Tuist.Push.Workers.DeliveryWorker
  alias Tuist.Push.Workers.NewPreviewWorker
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
  Resolves the OAuth grant behind `bearer` for `user`, as a sign-in of one of
  `apps`. Only unrevoked sign-ins with a refresh token qualify: through the
  Tuist app client (`Tuist.Environment.oauth_client_id/0`) for `"tuist"`, and
  through Luft's first-party client (`Tuist.OAuth.Clients.luft_client_id/0`)
  for `"luft"`, or the configured Luft server with `luft:app` for `"luft"`.
  Other OAuth clients, account tokens and other
  credentials return `{:error, :oauth_session_required}`. `bearer` must already
  be authenticated as `user` (`TuistWeb.AuthenticationPlug` verifies its
  signature and expiry).
  """
  def oauth_session(bearer, %User{} = user, apps \\ ["tuist"]) when is_binary(bearer) do
    Enum.find_value(apps, &app_session(&1, bearer, user)) ||
      ("luft" in apps && luft_server_session(bearer, user)) || {:error, :oauth_session_required}
  end

  defp app_session("tuist", bearer, %User{id: user_id}) do
    with client_id when is_binary(client_id) <- Environment.oauth_client_id(),
         %Token{} = grant <- OAuthGrants.find_bearer(bearer, client_id, user_id),
         {:ok, grant_id} <- OAuthGrants.root_id(grant) do
      {:ok, %{app: "tuist", oauth_grant_id: grant_id}}
    else
      _ -> nil
    end
  end

  defp app_session("luft", bearer, %User{id: user_id}) do
    with %Token{} = grant <- OAuthGrants.find_bearer(bearer, Clients.luft_client_id(), user_id),
         {:ok, grant_id} <- OAuthGrants.root_id(grant) do
      {:ok, %{app: "luft", oauth_grant_id: grant_id}}
    else
      _ -> nil
    end
  end

  @doc "Whether this is the configured Luft server's explicitly scoped app grant."
  def luft_app_session?(bearer, %User{} = user), do: not is_nil(luft_server_session(bearer, user))

  defp luft_server_session(bearer, %User{id: user_id}) do
    with client_id when is_binary(client_id) <- Clients.luft_server_client_id(),
         %Token{scope: scope} = grant <- OAuthGrants.find_bearer(bearer, client_id, user_id),
         true <- luft_app_scope?(scope),
         {:ok, grant_id} <- OAuthGrants.root_id(grant) do
      {:ok, %{app: "luft", oauth_grant_id: grant_id}}
    else
      _ -> nil
    end
  end

  defp luft_app_scope?(scope), do: Clients.luft_app_scope() in String.split(scope || "", " ", trim: true)

  @doc """
  Whether `bearer` belongs to an unrevoked sign-in through a first-party app:
  the Tuist app or Luft (`oauth_session/3`). The server trusts those as
  the signed-in user rather than through scopes.
  """
  def first_party_session?(bearer, %User{} = user) when is_binary(bearer) do
    Enum.any?(["tuist", "luft"], &match?({:ok, _session}, app_session(&1, bearer, user)))
  end

  @doc """
  Registers or refreshes `installation_id` for `user` under `session` (from
  `oauth_session/3`). `device` has `:platform` (`ios`, `macos` or `android`),
  `:token` and `:environment` (`sandbox` or `production`; Android is always
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
         {:ok, attrs} <- validate_device(device),
         :ok <- validate_app_platform(session.app, attrs.platform) do
      token_hash = Installation.token_hash(attrs.platform, attrs.token)

      installation_id
      |> locked(user, &upsert(&1, user, session, installation_id, attrs, token_hash))
      |> case do
        {:ok, result} -> result
        {:error, %Ecto.Changeset{}} -> {:error, :conflict}
      end
    end
  end

  @doc """
  Retires `installation_id` when it belongs to `user` and was registered from
  `app`. Unknown IDs become tombstones so a registration that arrives after its
  deletion is rejected. Other users' and other apps' installations are left
  untouched. Always `:ok` for a valid ID.
  """
  def unregister(%User{} = user, installation_id, app \\ "tuist") do
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

          %Installation{retired_at: nil, user_id: user_id, app: ^app} = installation when user_id == user.id ->
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
  it next tries to refresh its registration (`:removed`). Each app removes only
  its own devices, the ones its device list shows. Always `:ok`.
  """
  def remove_device(%User{id: user_id}, registration_id, app \\ "tuist") do
    with {:ok, registration_id} <- Ecto.UUID.cast(registration_id),
         %Installation{installation_id: installation_id} <-
           Repo.get_by(Installation, id: registration_id, user_id: user_id, app: app) do
      {:ok, _} =
        locked(installation_id, fn
          %Installation{retired_at: nil, user_id: ^user_id} = installation -> retire!(installation, "removed")
          _ -> :ok
        end)
    end

    :ok
  end

  @doc """
  The user's live installations of `app` whose OAuth grant is still active.
  Installations whose sign-in has ended are retired as `session_ended` instead
  of returned. This is the set notifications are delivered to.
  """
  def live_installations(user_id, app \\ "tuist") do
    Installation
    |> where([i], i.user_id == ^user_id and i.app == ^app and is_nil(i.retired_at))
    |> order_by([i], desc: i.last_registered_at)
    |> Repo.all()
    |> Enum.filter(fn installation ->
      session_active?(installation) or retire_session_ended(installation)
    end)
  end

  @doc """
  The server URL each Luft registration's profile belongs to, keyed by its ID.
  Call only after checking the registration's grant is active. Native sign-ins
  belong to this Tuist server; brokered ones belong to the fixed OIDC callback
  saved on their root grant. Read roots in one batch, not once per device, and
  never take a destination from registration parameters or a refreshed token.
  """
  def luft_server_urls(registrations) do
    roots =
      with [_ | _] <- registrations,
           client_id when is_binary(client_id) <- Clients.luft_server_client_id(),
           %Client{} = client <- Clients.get_client(client_id) do
        grant_ids = Enum.map(registrations, & &1.oauth_grant_id)

        Token
        |> where([t], t.id in ^grant_ids and t.client_id == ^client_id and t.type == "access_token")
        |> Repo.all()
        |> Map.new(fn grant ->
          {{grant.id, grant.sub}, callback_server_url(grant, client)}
        end)
      else
        _ -> %{}
      end

    Map.new(registrations, fn registration ->
      url = Map.get(roots, {registration.oauth_grant_id, to_string(registration.user_id)})
      {registration.id, url || Environment.app_url()}
    end)
  end

  defp callback_server_url(%Token{redirect_uri: callback, scope: scope}, %Client{redirect_uris: callbacks})
       when is_binary(callback) do
    with true <- luft_app_scope?(scope) and callback in callbacks,
         %URI{scheme: scheme, host: host, path: path, userinfo: nil, query: nil, fragment: nil} = uri <-
           URI.parse(callback),
         true <- is_binary(path) and String.ends_with?(path, "/auth/callback"),
         true <- is_binary(host) and host != "" and not String.contains?(host, "*"),
         true <- scheme == "https" or (scheme == "http" and host in ["localhost", "127.0.0.1", "::1"]),
         false <- Regex.match?(~r/[\s\p{Cc}\\]/u, callback) do
      # Config.redirect_uri appends this suffix to Luft's public URL, which
      # may itself include a deployment prefix. Keep that prefix in profiles.
      URI.to_string(%{uri | path: String.replace_suffix(path, "/auth/callback", "")})
    else
      _ -> nil
    end
  end

  defp callback_server_url(_grant, _client), do: nil

  @doc """
  Queues a new-preview notification for `preview` (see
  `Tuist.Push.Workers.NewPreviewWorker`). Does nothing on servers with neither
  an APNs key nor FCM credentials.
  """
  def notify_new_preview(%{id: preview_id}) do
    if APNs.configured?() or FCM.configured?() do
      {:ok, _job} = %{"preview_id" => preview_id} |> NewPreviewWorker.new() |> Oban.insert()
    end

    :ok
  end

  @doc "Compatibility no-op while old callers drain; Luft owns conversation notifications."
  def notify_thread_finished(_thread, _status), do: :ok

  @doc "Dispatches Luft-rendered notifications as the exact authenticated owning user, never a recipient ID."
  def dispatch_luft(%User{} = user, bearer, input) do
    with {:ok, %{app: "luft"} = session} <- luft_server_session(bearer, user),
         true <- grant_active?("luft", session.oauth_grant_id, user.id) do
      case input do
        %{"kind" => "liveactivity"} ->
          LiveActivities.dispatch(user, session, input)

        %{"kind" => "alert", "notification_id" => id, "payload" => payload}
        when is_binary(id) and byte_size(id) in 1..200 and is_map(payload) ->
          dispatch_alert(user, session, id, payload)

        _ ->
          {:error, :invalid}
      end
    else
      _ -> {:error, :forbidden}
    end
  end

  defp dispatch_alert(user, session, id, payload) do
    with %{"aps" => %{"alert" => %{"title" => title, "body" => body}}, "url" => path} <- payload,
         true <- is_binary(title) and is_binary(body) and byte_size(JSON.encode!(payload)) <= 4096,
         true <- is_binary(path) and String.starts_with?(path, "/") and not String.starts_with?(path, "//") do
      installations = Enum.filter(live_installations(user.id, "luft"), &(&1.oauth_grant_id == session.oauth_grant_id))
      urls = luft_server_urls(installations)

      Enum.each(installations, fn installation ->
        # Only the validated root callback chooses the origin, never a request parameter.
        payload = Map.put(payload, "url", String.trim_trailing(Map.fetch!(urls, installation.id), "/") <> path)

        args = %{
          "registration_id" => installation.id,
          "oauth_grant_id" => session.oauth_grant_id,
          "notification_id" => id,
          "payload" => payload
        }

        {:ok, _} =
          args
          |> DeliveryWorker.new(
            unique: [
              period: :infinity,
              keys: [:registration_id, :oauth_grant_id, :notification_id],
              states: [:available, :scheduled, :executing, :retryable, :completed]
            ]
          )
          |> Oban.insert()
      end)

      :ok
    else
      _ -> {:error, :invalid}
    end
  end

  @doc "The APNs topic, the bundle ID, of the app `installation` belongs to."
  def apns_topic(%Installation{app: "luft"}), do: "dev.tuist.code"
  def apns_topic(%Installation{}), do: Environment.apns_topic()

  @doc """
  Retires `installation` as `rejected` after the push provider refused its token,
  unless it has registered a different token since.
  """
  def retire_rejected(%Installation{id: id, token_hash: token_hash}) do
    Installation
    |> where([i], i.id == ^id and i.token_hash == ^token_hash and is_nil(i.retired_at))
    |> Repo.update_all(set: retired_fields("rejected"))

    :ok
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

  defp session_active?(%Installation{} = installation),
    do: grant_active?(installation.app, installation.oauth_grant_id, installation.user_id)

  @doc """
  Whether the sign-in `grant_id` of `user_id` through `app`'s native OAuth
  client or the scoped Luft server grant is still active. Raises on database errors, so a transient failure
  never retires a live registration.
  """
  def grant_active?(app, grant_id, user_id) do
    client_id = if app == "luft", do: Clients.luft_client_id(), else: Environment.oauth_client_id()

    native_grant_active?(client_id, grant_id, user_id) or
      (app == "luft" and luft_server_grant_active?(grant_id, user_id))
  end

  defp native_grant_active?(client_id, grant_id, user_id) do
    case Clients.get_client(client_id) do
      %Client{refresh_token_ttl: ttl} ->
        match?({:ok, _scope}, OAuthGrants.active_scope(grant_id, client_id, user_id, ttl))

      nil ->
        false
    end
  end

  defp luft_server_grant_active?(grant_id, user_id) do
    with client_id when is_binary(client_id) <- Clients.luft_server_client_id(),
         %Client{refresh_token_ttl: ttl} <- Clients.get_client(client_id),
         {:ok, scope} <- OAuthGrants.active_scope(grant_id, client_id, user_id, ttl) do
      luft_app_scope?(scope)
    else
      _ -> false
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
  # same installation, including its very first insert. Registration also takes
  # the user's lock, first, so enforcing the device cap is serialized per user
  # and never waits on another installation while holding the user's lock.
  defp locked(installation_id, user \\ nil, fun) do
    Repo.transaction(fn ->
      if user, do: advisory_lock!("push_user:#{user.id}")
      advisory_lock!("push_installation:" <> installation_id)

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

  defp upsert(%Installation{app: app}, _user, %{app: other}, _installation_id, _attrs, _hash) when app != other,
    do: {:error, :conflict}

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
      app: session.app,
      oauth_grant_id: session.oauth_grant_id,
      platform: attrs.platform,
      device_name: attrs.name,
      environment: attrs.environment,
      token: attrs.token,
      token_hash: hash,
      last_registered_at: now
    })
    |> Ecto.Changeset.unique_constraint(:installation_id)
    |> Ecto.Changeset.unique_constraint(:token_hash, name: :push_installations_live_token_hash_index)
    |> Repo.insert_or_update()
    |> case do
      {:ok, saved} ->
        evict_oldest!(user.id, session.app)
        {:ok, saved}

      {:error, changeset} ->
        Repo.rollback(changeset)
    end
  end

  defp advisory_lock!(key), do: Repo.query!("SELECT pg_advisory_xact_lock(hashtextextended($1, 0))", [key])

  # Per app, so one app's registrations never push out the other's devices.
  defp evict_oldest!(user_id, app) do
    keep =
      Installation
      |> where([i], i.user_id == ^user_id and i.app == ^app and is_nil(i.retired_at))
      |> order_by([i], desc: i.last_registered_at, desc: i.id)
      |> limit(@max_live_per_user)
      |> select([i], i.id)

    Installation
    |> where([i], i.user_id == ^user_id and i.app == ^app and is_nil(i.retired_at) and i.id not in subquery(keep))
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

  # Every app shares the server's one FCM project, so an Android "Luft"
  # registration could carry the Tuist app's token and deliver thread
  # notifications to it. Luft Android has no push support yet either.
  defp validate_app_platform("luft", "android"), do: {:error, :invalid}
  defp validate_app_platform(_app, _platform), do: :ok

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

  defp validate_token(platform, token) when platform in ["ios", "macos"] do
    if Regex.match?(@apns_token, token), do: {:ok, String.downcase(token)}, else: :error
  end

  defp validate_token("android", token) do
    if Regex.match?(@android_token, token), do: {:ok, token}, else: :error
  end

  defp validate_token(_platform, _token), do: :error

  defp valid_environment?(platform, environment) when platform in ["ios", "macos"],
    do: environment in ["sandbox", "production"]

  defp valid_environment?("android", environment), do: environment == "production"
end
