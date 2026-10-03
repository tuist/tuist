defmodule Atlas.MCP do
  @moduledoc """
  Context for configured upstream MCP servers and per-user OAuth sessions.
  """

  import Ecto.Query

  alias Atlas.Audit
  alias Atlas.MCP.OAuth
  alias Atlas.MCP.OAuthSession
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
        if transient_refresh_error?(reason) do
          {:error, :refresh_unavailable}
        else
          mark_oauth_session_needs_authorization(session, reason)
          {:error, {:refresh_failed, reason}}
        end
    end
  end

  # A timeout, rate limit or upstream outage is not evidence of revocation.
  # Preserve the refresh credential for the next request/worker run, but do not
  # return an expired access token while refresh is unavailable.
  defp transient_refresh_error?({:http, status, _body}), do: status == 429 or status in 500..599
  defp transient_refresh_error?(%Req.TransportError{}), do: true
  defp transient_refresh_error?(_reason), do: false

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
