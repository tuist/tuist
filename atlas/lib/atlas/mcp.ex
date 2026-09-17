defmodule Atlas.MCP do
  @moduledoc """
  Context for configured upstream MCP servers, per-user OAuth sessions, and the
  operator grants that elevate them.
  """

  import Ecto.Query

  alias Atlas.Audit
  alias Atlas.MCP.GrantRequest
  alias Atlas.MCP.OAuth
  alias Atlas.MCP.OAuthSession
  alias Atlas.MCP.OperatorGrant
  alias Atlas.MCP.Proxy
  alias Atlas.MCP.Proxy.Server
  alias Atlas.Repo
  alias Atlas.Users
  alias Atlas.Users.User

  def list_servers(%User{} = user) do
    Enum.map(Proxy.configured_servers(), fn %Server{} = server ->
      session = oauth_session_for(user, server)

      %{
        server: server,
        session: session,
        status: session_status(server, session)
      }
    end)
  end

  def get_server(name), do: Proxy.fetch_server(name)

  def get_oauth_session(%User{id: user_id}, server_name) when is_binary(server_name) do
    Repo.get_by(OAuthSession, user_id: user_id, server_name: server_name)
  end

  def access_token_for(%User{} = user, %Server{auth_type: :oauth2} = server) do
    case oauth_session_for(user, server) do
      nil ->
        {:error, :authorization_required}

      %OAuthSession{} = session ->
        if OAuthSession.valid?(session) do
          {:ok, session.access_token}
        else
          refresh_access_token(session, server)
        end
    end
  end

  def access_token_for(_user, _server), do: {:error, :unsupported_auth_type}

  def refresh_expiring_oauth_sessions(opts \\ []) do
    Audit.with_context(%{interface: "worker"}, fn ->
      do_refresh_expiring_oauth_sessions(opts)
    end)
  end

  defp do_refresh_expiring_oauth_sessions(opts) do
    threshold_seconds = Keyword.get(opts, :threshold_seconds, 600)
    cutoff = DateTime.utc_now() |> DateTime.add(threshold_seconds, :second) |> DateTime.truncate(:second)

    servers =
      Proxy.configured_servers()
      |> Enum.filter(&(&1.auth_type == :oauth2))
      |> Map.new(&{&1.name, &1})

    sessions =
      OAuthSession
      |> where([s], s.status == "authorized")
      |> where([s], not is_nil(s.refresh_token))
      |> where([s], s.server_name in ^Map.keys(servers))
      |> where([s], is_nil(s.expires_at) or s.expires_at <= ^cutoff)
      |> Repo.all()

    summary =
      sessions
      |> Enum.map(fn session ->
        refresh_expiring_oauth_session(session.id, Map.fetch!(servers, session.server_name), cutoff)
      end)
      |> Enum.reduce(%{refreshed: 0, skipped: 0, failed: 0}, fn
        {:ok, :refreshed}, acc -> Map.update!(acc, :refreshed, &(&1 + 1))
        {:ok, :skipped}, acc -> Map.update!(acc, :skipped, &(&1 + 1))
        {:ok, :fresh}, acc -> Map.update!(acc, :skipped, &(&1 + 1))
        {:error, _reason}, acc -> Map.update!(acc, :failed, &(&1 + 1))
      end)

    {:ok, summary}
  end

  def client_for(%OAuthSession{client_id: client_id, client_secret: client_secret}, %Server{} = server) do
    %{
      client_id: client_id || server.client_id,
      client_secret: client_secret || server.client_secret
    }
  end

  def upsert_oauth_session(%User{} = user, %Server{} = server, token_attrs) do
    attrs =
      token_attrs
      |> Map.merge(%{
        status: "authorized",
        last_error: nil
      })
      |> Map.put_new(:token_type, "Bearer")
      |> Map.put_new(:scopes, [])

    existing = get_oauth_session(user, server.name)

    result =
      case existing do
        nil ->
          %OAuthSession{user_id: user.id, server_name: server.name}
          |> OAuthSession.changeset(attrs)
          |> Repo.insert()

        %OAuthSession{} = session ->
          session
          |> OAuthSession.changeset(attrs)
          |> Repo.update()
      end

    case result do
      {:ok, session} = success ->
        Audit.record(
          if(existing, do: "mcp_oauth_session.reauthorized", else: "mcp_oauth_session.authorized"),
          %{
            target_type: "mcp_oauth_session",
            target_id: session.id,
            target_label: server.name,
            metadata: %{
              "path" => "/admin/mcps",
              "server_name" => server.name,
              "status" => session.status,
              "expires_at" => session.expires_at,
              "scopes" => session.scopes
            }
          },
          actor: user,
          interface: "dashboard"
        )

        success

      error ->
        error
    end
  end

  @doc """
  Stores a user's operator grant for an upstream server, replacing any previous
  one. Returns `{:error, :unreadable_grant}` when the token's payload cannot be
  read — Atlas does not verify grants, only reads enough to key and expire them.

  Pass `:expected_account_handle` to refuse a grant for any other account. The
  comparison happens before anything is written, so a grant for an account the
  operator did not ask about cannot displace the one they already hold, and
  cannot leave an audit entry claiming it was stored.

  Only `:read` grants are stored. An `:admin` grant exists so an operator can act
  on a customer's behalf after a Slack approval; Atlas is a place to look at
  production, so it has no use for one, and refusing it here means the upstream's
  own tier check — not this proxy's tool list — is what stands between an
  investigation and a write.
  """
  def put_operator_grant(%User{} = user, server_name, token, opts \\ [])
      when is_binary(server_name) and is_binary(token) do
    {expected_handle, opts} = Keyword.pop(opts, :expected_account_handle)

    with {:ok, %{account_handle: handle, tier: tier, expires_at: expires_at}} <- OperatorGrant.describe(token),
         :ok <- ensure_expected_account(expected_handle, handle),
         :ok <- ensure_read_tier(tier) do
      attrs = %{
        server_name: server_name,
        account_handle: handle,
        token: token,
        expires_at: expires_at
      }

      existing = get_operator_grant(user, server_name)

      result =
        case existing do
          nil ->
            %OperatorGrant{user_id: user.id, server_name: server_name}
            |> OperatorGrant.changeset(attrs)
            |> Repo.insert()

          %OperatorGrant{} = grant ->
            grant
            |> OperatorGrant.changeset(attrs)
            |> Repo.update()
        end

      with {:ok, grant} <- result do
        audit_operator_grant(
          if(existing, do: "mcp.operator_grant_replaced", else: "mcp.operator_grant_stored"),
          grant,
          user,
          opts
        )

        {:ok, grant}
      end
    end
  end

  defp ensure_read_tier(:read), do: :ok
  defp ensure_read_tier(tier), do: {:error, {:unsupported_grant_tier, tier}}

  defp ensure_expected_account(nil, _handle), do: :ok

  defp ensure_expected_account(expected, handle) do
    if String.downcase(expected) == String.downcase(handle) do
      :ok
    else
      {:error, {:account_mismatch, expected}}
    end
  end

  def get_operator_grant(%User{id: user_id}, server_name) when is_binary(server_name) do
    Repo.get_by(OperatorGrant, user_id: user_id, server_name: server_name)
  end

  @doc "The user's grant for a server when it is still active, otherwise nil."
  def active_operator_grant(%User{} = user, server_name) do
    case get_operator_grant(user, server_name) do
      %OperatorGrant{} = grant -> if OperatorGrant.active?(grant), do: grant
      _ -> nil
    end
  end

  @doc """
  The user's grant for a server when it is safe to forward upstream, otherwise
  nil.

  The tier is re-read from the token rather than from a column, so what is
  checked is the same bytes that travel in the header and no stored copy can
  disagree with them. `put_operator_grant/4` already refuses anything but a read
  grant, which leaves this covering the grants that predate that rule — and
  meaning a later caller cannot reintroduce the gap by writing a grant some
  other way.
  """
  def proxyable_operator_grant(%User{} = user, server_name) do
    with %OperatorGrant{token: token} = grant <- active_operator_grant(user, server_name),
         {:ok, %{tier: :read}} <- OperatorGrant.describe(token) do
      grant
    else
      _ -> nil
    end
  end

  def delete_operator_grant(%User{} = user, server_name, opts \\ []) do
    case get_operator_grant(user, server_name) do
      %OperatorGrant{} = grant ->
        with {:ok, deleted} <- Repo.delete(grant) do
          audit_operator_grant("mcp.operator_grant_cleared", deleted, user, opts)
          {:ok, deleted}
        end

      nil ->
        {:ok, nil}
    end
  end

  @doc """
  Records that `user` is asking for a grant and returns where they justify it.

  The pending request's id rides the round trip as `state`, so the grant that
  comes back can be tied to someone having asked for it. Ops preserves existing
  query parameters when it appends the token, so the state survives the redirect.

  Returns the `:url` a person is sent to along with the `:state` and
  `:expires_at` behind it, so a caller can describe the round trip to whatever
  is rendering the refusal rather than only to whoever reads it.
  """
  def start_operator_grant_request(%User{} = user, server_name, account_handle)
      when is_binary(server_name) and is_binary(account_handle) do
    with {:ok, request} <- live_or_new_grant_request(user, server_name, account_handle) do
      return_to =
        AtlasWeb.Endpoint.url() <>
          "/mcps/#{URI.encode(server_name)}/operator-grant?" <> URI.encode_query(%{"state" => request.id})

      query = URI.encode_query(%{"account" => account_handle, "return_to" => return_to})

      {:ok,
       %{
         url: ops_reason_form_url() <> "?" <> query,
         state: request.id,
         account_handle: request.account_handle,
         expires_at: request.expires_at
       }}
    end
  end

  # A refused tool call can be retried in a loop, and inserting a row per
  # attempt would leave a trail of keys behind for one question. Reusing a live
  # request costs nothing: the callback consumes whichever row it is handed, so
  # the round trip stays single-use either way.
  defp live_or_new_grant_request(%User{} = user, server_name, account_handle) do
    case live_grant_request(user, server_name, account_handle) do
      %GrantRequest{} = request ->
        {:ok, request}

      nil ->
        %GrantRequest{user_id: user.id}
        |> GrantRequest.changeset(%{
          server_name: server_name,
          account_handle: account_handle,
          expires_at: GrantRequest.expires_at()
        })
        |> Repo.insert()
    end
  end

  defp live_grant_request(%User{id: user_id}, server_name, account_handle) do
    GrantRequest
    |> where(
      [r],
      r.user_id == ^user_id and r.server_name == ^server_name and r.account_handle == ^account_handle and
        r.expires_at > ^DateTime.utc_now()
    )
    |> order_by([r], desc: r.expires_at)
    |> limit(1)
    |> Repo.one()
  end

  @doc """
  Consumes a pending grant request. Single-use: the row is deleted whether or
  not it was still live, so a replayed link cannot be followed twice.
  """
  def consume_operator_grant_request(%User{id: user_id}, server_name, state) when is_binary(state) do
    with {:ok, id} <- cast_request_id(state),
         %GrantRequest{user_id: ^user_id, server_name: ^server_name} = request <- Repo.get(GrantRequest, id),
         {:ok, _deleted} <- Repo.delete(request) do
      if GrantRequest.active?(request), do: {:ok, request}, else: {:error, :expired_request}
    else
      _ -> {:error, :unknown_request}
    end
  end

  def consume_operator_grant_request(_user, _server_name, _state), do: {:error, :unknown_request}

  defp cast_request_id(state) do
    case Ecto.UUID.cast(state) do
      {:ok, id} -> {:ok, id}
      :error -> :error
    end
  end

  @doc "Removes pending grant requests that were never completed."
  def prune_expired_grant_requests do
    {count, _} =
      GrantRequest
      |> where([r], r.expires_at <= ^DateTime.utc_now())
      |> Repo.delete_all()

    count
  end

  defp ops_reason_form_url do
    Application.get_env(:atlas, :ops)[:reason_form_url] || "https://ops.tuist.dev/grants/new"
  end

  # Elevation is exactly the kind of thing that must be reconstructable later:
  # who took it, for which customer, through which interface, and until when.
  # The token itself is never recorded — it is a live bearer, and the audit row
  # outlives it.
  # The actor is passed rather than inherited: the callback that stores a grant
  # is a controller request, not the LiveView process that installs the dashboard
  # audit context, so an inherited context would attribute the most
  # consequential of these three actions to nobody.
  defp audit_operator_grant(action, %OperatorGrant{} = grant, %User{} = user, opts) do
    Audit.record(
      action,
      %{
        target_type: "mcp_operator_grant",
        target_id: grant.id,
        target_label: "#{grant.server_name}/#{grant.account_handle}",
        metadata: %{
          server_name: grant.server_name,
          account_handle: grant.account_handle,
          expires_at: grant.expires_at
        }
      },
      Keyword.merge([actor: user, interface: "dashboard"], opts)
    )
  end

  @doc "Removes grants past their expiry. Expired grants authorize nothing, but they should not linger either."
  def prune_expired_operator_grants do
    {count, _} =
      OperatorGrant
      |> where([g], g.expires_at <= ^DateTime.utc_now())
      |> Repo.delete_all()

    count
  end

  def mark_oauth_session_needs_authorization(%OAuthSession{} = session, error) do
    result =
      session
      |> OAuthSession.changeset(%{
        status: "needs_authorization",
        last_error: inspect(error),
        access_token: nil
      })
      |> Repo.update()

    case result do
      {:ok, updated} = success ->
        Audit.record(
          "mcp_oauth_session.authorization_required",
          %{
            target_type: "mcp_oauth_session",
            target_id: updated.id,
            target_label: updated.server_name,
            metadata: %{
              "path" => "/admin/mcps",
              "server_name" => updated.server_name,
              "status" => updated.status
            }
          }
        )

        success

      result ->
        result
    end
  end

  defp oauth_session_for(%User{} = user, %Server{auth_type: :oauth2, shared_oauth: true} = server) do
    # Shared OAuth is a server-wide credential for authenticated Atlas MCP users.
    # Only enable it for upstream systems where the configured session is allowed
    # to represent the Atlas workspace rather than an individual user.
    shared_oauth_session(server) || get_oauth_session(user, server.name)
  end

  defp oauth_session_for(%User{} = user, %Server{} = server), do: get_oauth_session(user, server.name)

  defp shared_oauth_session(%Server{shared_oauth_user_email: email} = server) when is_binary(email) and email != "" do
    case Users.get_user_by_email(email) do
      %User{} = user -> get_oauth_session(user, server.name)
      nil -> nil
    end
  end

  defp shared_oauth_session(%Server{} = server) do
    OAuthSession
    |> where([s], s.server_name == ^server.name)
    |> order_by([s], desc: s.status == "authorized", desc: s.updated_at)
    |> limit(1)
    |> Repo.one()
  end

  defp refresh_access_token(%OAuthSession{} = session, %Server{} = server) do
    result =
      Repo.transaction(fn ->
        session =
          Repo.one(
            from s in OAuthSession,
              where: s.id == ^session.id,
              lock: "FOR UPDATE"
          )

        cond do
          is_nil(session) ->
            {:error, :authorization_required}

          OAuthSession.valid?(session) ->
            {:ok, session.access_token}

          not OAuthSession.refreshable?(session) ->
            mark_oauth_session_needs_authorization(session, :missing_refresh_token)
            {:error, :authorization_required}

          true ->
            refresh_locked_session(server, session)
        end
      end)

    case result do
      {:ok, {:ok, access_token}} -> {:ok, access_token}
      {:ok, {:error, reason}} -> {:error, reason}
      {:error, reason} -> {:error, reason}
    end
  end

  defp refresh_expiring_oauth_session(session_id, %Server{} = server, cutoff) do
    result =
      Repo.transaction(fn ->
        session_id
        |> locked_oauth_session()
        |> refresh_locked_session_if_expiring(server, cutoff)
      end)

    case result do
      {:ok, outcome} -> outcome
      {:error, reason} -> {:error, reason}
    end
  end

  defp locked_oauth_session(session_id) do
    Repo.one(
      from s in OAuthSession,
        where: s.id == ^session_id,
        lock: "FOR UPDATE SKIP LOCKED"
    )
  end

  defp refresh_locked_session_if_expiring(nil, _server, _cutoff), do: {:ok, :skipped}

  defp refresh_locked_session_if_expiring(%OAuthSession{status: status}, _server, _cutoff) when status != "authorized",
    do: {:ok, :skipped}

  defp refresh_locked_session_if_expiring(%OAuthSession{} = session, %Server{} = server, cutoff) do
    if oauth_session_expiring?(session, cutoff) do
      case refresh_locked_session(server, session) do
        {:ok, _access_token} -> {:ok, :refreshed}
        {:error, _reason} = error -> error
      end
    else
      {:ok, :fresh}
    end
  end

  defp oauth_session_expiring?(%OAuthSession{expires_at: nil}, _cutoff), do: true

  defp oauth_session_expiring?(%OAuthSession{expires_at: expires_at}, cutoff) do
    DateTime.compare(expires_at, cutoff) in [:lt, :eq]
  end

  defp refresh_locked_session(%Server{} = server, %OAuthSession{} = session) do
    client = client_for(session, server)

    case OAuth.refresh_token(server, session.refresh_token, client) do
      {:ok, attrs} ->
        attrs =
          if attrs.refresh_token in [nil, ""] do
            Map.put(attrs, :refresh_token, session.refresh_token)
          else
            attrs
          end

        {:ok, session} =
          session
          |> OAuthSession.changeset(Map.merge(attrs, %{status: "authorized", last_error: nil}))
          |> Repo.update()

        audit_oauth_session_refresh(session)

        {:ok, session.access_token}

      {:error, reason} ->
        mark_oauth_session_needs_authorization(session, reason)
        {:error, {:refresh_failed, reason}}
    end
  end

  defp audit_oauth_session_refresh(%OAuthSession{} = session) do
    Audit.record(
      "mcp_oauth_session.refreshed",
      %{
        target_type: "mcp_oauth_session",
        target_id: session.id,
        target_label: session.server_name,
        metadata: %{
          "path" => "/admin/mcps",
          "server_name" => session.server_name,
          "status" => session.status,
          "expires_at" => session.expires_at
        }
      }
    )
  end

  defp session_status(%Server{auth_type: :bearer_token}, _session), do: :shared_credentials
  defp session_status(%Server{auth_type: :none}, _session), do: :connected
  defp session_status(%Server{auth_type: :oauth2}, nil), do: :not_connected

  defp session_status(%Server{auth_type: :oauth2}, %OAuthSession{status: "needs_authorization"}),
    do: :needs_authorization

  defp session_status(%Server{auth_type: :oauth2}, %OAuthSession{} = session),
    do: if(OAuthSession.valid?(session), do: :connected, else: :expired)
end
