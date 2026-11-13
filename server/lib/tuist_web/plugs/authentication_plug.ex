defmodule TuistWeb.AuthenticationPlug do
  @moduledoc """
  A plug that deals with authentication of requests.
  """
  use TuistWeb, :controller

  import Plug.Conn

  alias Tuist.Accounts
  alias Tuist.Accounts.AccountToken
  alias Tuist.Accounts.AuthenticatedAccount
  alias Tuist.Accounts.User
  alias Tuist.Authentication.SubjectCache
  alias Tuist.Authentication.UnavailableError
  alias Tuist.OIDC
  alias Tuist.Projects
  alias Tuist.Projects.Project
  alias Tuist.Sandboxes
  alias TuistWeb.API.CacheController
  alias TuistWeb.Errors.ServiceUnavailableError
  alias TuistWeb.Headers
  alias TuistWeb.RequestOrigin
  alias TuistWeb.WarningsHeaderPlug

  @bounded_write_controllers [
    TuistWeb.API.AnalyticsController,
    TuistWeb.API.BuildsController,
    TuistWeb.API.TestsController,
    TuistWeb.API.GradleController,
    TuistWeb.API.MixController,
    TuistWeb.API.BazelController,
    TuistWeb.API.BundlesController
  ]

  @bounded_read_controllers @bounded_write_controllers ++
                              [
                                CacheController,
                                TuistWeb.API.PreviewsController,
                                TuistWeb.API.ProjectsController,
                                TuistWeb.API.GradleTasksController,
                                TuistWeb.API.GradleBuildStepsController,
                                TuistWeb.API.BazelBuildStepsController
                              ]

  @mcp_resource_metadata_path "/.well-known/oauth-protected-resource/mcp"

  def init(opts) when opts in [:load_authenticated_subject, :load_agent_identity], do: opts
  def init({:require_authentication, _} = opts), do: opts

  def call(conn, :load_authenticated_subject) do
    conn = configure_caching(conn)
    token = TuistWeb.Authentication.get_authorization_token_from_conn(conn)

    if token do
      get_authenticated_subject(conn, token)
    else
      conn
    end
  rescue
    UnavailableError ->
      reraise ServiceUnavailableError, [message: "Authentication temporarily unavailable."], __STACKTRACE__
  end

  # A coding agent in a sandbox reaches the MCP endpoint with its own identity
  # token instead of a Tuist credential: an Amp orb's ID token minted for this
  # instance's origin (`Bearer ${amp:id-token}`) or a Claude Code session token.
  # It resolves through the same connections as the OIDC exchange and reads the
  # connected account's projects; the `mcp` preset holds no write scope. Runs
  # after `:load_authenticated_subject`, so Tuist credentials keep precedence.
  def call(conn, :load_agent_identity) do
    with false <- TuistWeb.Authentication.authenticated?(conn),
         token when is_binary(token) <- TuistWeb.Authentication.get_authorization_token_from_conn(conn),
         {:ok, identity} <- OIDC.agent_claims(token, instance_origin()) do
      case agent_account(identity) do
        {:ok, account} ->
          assign(conn, :current_subject, %AuthenticatedAccount{
            account: account,
            scopes: [AccountToken.mcp_scope()],
            all_projects: true
          })

        error ->
          assign(conn, :agent_identity_error, agent_identity_error(error))
      end
    else
      _ -> conn
    end
  end

  def call(conn, {:require_authentication, opts}) do
    response_type = Keyword.get(opts, :response_type, :open_api)

    if TuistWeb.Authentication.authenticated?(conn) do
      conn
    else
      case response_type do
        :open_api ->
          conn
          |> put_status(:unauthorized)
          |> json(%{message: "You need to be authenticated to access this resource."})
          |> halt()

        :mcp ->
          origin = RequestOrigin.from_conn(conn)

          conn
          |> put_resp_header(
            "www-authenticate",
            ~s(Bearer realm="tuist-mcp", resource_metadata="#{origin}#{@mcp_resource_metadata_path}")
          )
          |> put_status(:unauthorized)
          |> json(%{
            error: "invalid_token",
            error_description: conn.assigns[:agent_identity_error] || "Missing or invalid access token.",
            auth_md: "#{origin}/auth.md",
            authentication_instructions:
              "Fetch auth_md and follow Tuist's discovery, registration, identity-assertion exchange, and claim-polling flow before falling back to browser Open Authorization."
          })
          |> halt()
      end
    end
  end

  defp get_authenticated_subject(conn, token) do
    bounded = bounded?(conn)
    conn = assign(conn, :auth_freshness, if(bounded, do: :bounded, else: :strict))

    case resolve_subject(conn, token, bounded) do
      %Project{} = project ->
        put_project(conn, token, project)

      %User{} = user ->
        TuistWeb.Authentication.put_current_user(conn, user)

      %AuthenticatedAccount{} = subject ->
        conn
        |> assign(:current_subject, subject)
        |> put_claimed_agent_user(subject)

      {:error, _reason} ->
        raise ServiceUnavailableError, "Authentication temporarily unavailable."

      nil ->
        conn
    end
  end

  defp put_project(conn, token, %Project{account: account} = project) do
    cli_version = Headers.get_cli_version(conn)

    conn =
      if Projects.legacy_token?(token) and not is_nil(cli_version) and
           Version.compare(cli_version, Version.parse!("4.20.0")) == :gt do
        WarningsHeaderPlug.put_warning(
          conn,
          "The project token you are using is deprecated. Please create a new token by running `tuist projects token create #{account.name}/#{project.name}."
        )
      else
        conn
      end

    TuistWeb.Authentication.put_current_project(conn, project)
  end

  defp resolve_subject(_conn, token, false), do: Tuist.Authentication.authenticated_subject(token)

  defp resolve_subject(conn, token, true) do
    case SubjectCache.fetch(token, Map.get(conn.assigns, :auth_cache_opts, [])) do
      {:ok, nil} -> nil
      {:ok, snapshot} -> snapshot.subject
      {:error, :unavailable} -> raise ServiceUnavailableError, "Authentication temporarily unavailable."
    end
  end

  defp bounded?(conn) do
    {controller, action} = route(conn)

    cache_write? =
      controller == CacheController and
        action in [:upload_cache_action_item, :multipart_start, :multipart_generate_url, :multipart_complete]

    Map.get(conn.assigns, :caching, false) and conn.assigns[:auth_freshness] != :strict and
      (bounded_read?(conn, controller, action) or cache_write? or bounded_write?(conn, controller, action))
  end

  defp bounded_read?(conn, controller, action) do
    conn.method in ["GET", "HEAD"] and controller in @bounded_read_controllers and action != :token
  end

  defp bounded_write?(conn, controller, action) do
    conn.method == "POST" and controller in @bounded_write_controllers and
      action in [
        :create,
        :create_build,
        :multipart_start,
        :multipart_generate_url,
        :multipart_complete,
        :multipart_start_project,
        :multipart_generate_url_project,
        :multipart_complete_project
      ]
  end

  defp route(conn) do
    case Phoenix.Router.route_info(TuistWeb.Router, conn.method, conn.request_path, conn.host) do
      %{plug: controller, plug_opts: action} -> {controller, action}
      _ -> {conn.private[:phoenix_controller], conn.private[:phoenix_action]}
    end
  end

  defp configure_caching(conn) do
    if conn.assigns[:auth_cache_default] do
      assign(conn, :caching, Map.get(conn.assigns, :caching, not Tuist.Environment.test?()))
    else
      conn
    end
  end

  defp put_claimed_agent_user(conn, %AuthenticatedAccount{scopes: scopes, agent_registration_id: registration_id})
       when not is_nil(registration_id) do
    if conn.request_path == "/mcp" and "mcp" in scopes do
      case Accounts.claimed_protocol_agent_user(registration_id) do
        %User{} = user -> TuistWeb.Authentication.put_current_user(conn, user)
        nil -> conn
      end
    else
      conn
    end
  end

  defp put_claimed_agent_user(conn, %AuthenticatedAccount{scopes: scopes, token_id: token_id})
       when not is_nil(token_id) do
    if conn.request_path == "/mcp" and "mcp" in scopes do
      case Accounts.claimed_agent_registration_user(token_id) do
        %User{} = user -> TuistWeb.Authentication.put_current_user(conn, user)
        nil -> conn
      end
    else
      conn
    end
  end

  # An access token a user granted through the browser authorization flow, or
  # one issued when they claimed an `auth.md` registration.
  defp put_claimed_agent_user(conn, %AuthenticatedAccount{scopes: scopes, issued_by: %User{} = user}) do
    if conn.request_path == "/mcp" and "mcp" in scopes do
      TuistWeb.Authentication.put_current_user(conn, user)
    else
      conn
    end
  end

  defp put_claimed_agent_user(conn, _subject), do: conn

  defp agent_account(%{amp_workspace_id: workspace_id, amp_project_id: project_id}) when is_binary(workspace_id),
    do: Accounts.amp_workspace_account(workspace_id, project_id, nil)

  defp agent_account(%{amp_workspace_id: nil}), do: {:error, :amp_workspace_not_connected}

  defp agent_account(%{claude_code_environment_id: environment_id}),
    do: Sandboxes.claude_code_environment_account(environment_id)

  defp agent_identity_error({:error, :amp_workspace_not_connected}),
    do:
      "This Amp workspace or project is not connected to a Tuist account. An account administrator can connect it under Settings, Integrations, Amp. Amp threads outside a workspace are not supported."

  defp agent_identity_error({:error, :ambiguous_amp_workspace, account_handles}),
    do:
      "This Amp workspace is connected to several Tuist accounts (#{Enum.join(account_handles, ", ")}), so its identity token does not name one. Connect it to a single account, or use a Tuist credential."

  defp agent_identity_error({:error, :claude_code_environment_not_connected}),
    do: "This Claude Code environment is not connected to a Tuist account with sandboxes."

  # The audience Amp gives `${amp:id-token}`: the HTTPS origin of the MCP URL,
  # with a nondefault port. Using this instance's own origin keeps a token
  # minted for one environment from being accepted by another.
  defp instance_origin do
    %URI{scheme: scheme, host: host, port: port} = URI.parse(Tuist.Environment.app_url(route_type: :app))

    if port == URI.default_port(scheme), do: "#{scheme}://#{host}", else: "#{scheme}://#{host}:#{port}"
  end
end
