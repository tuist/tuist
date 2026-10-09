defmodule TuistWeb.AuthenticationPlug do
  @moduledoc """
  A plug that deals with authentication of requests.
  """
  use TuistWeb, :controller

  import Plug.Conn

  alias Tuist.Accounts
  alias Tuist.Accounts.AuthenticatedAccount
  alias Tuist.Accounts.User
  alias Tuist.Authentication.SubjectCache
  alias Tuist.Authentication.UnavailableError
  alias Tuist.Projects
  alias Tuist.Projects.Project
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

  def init(:load_authenticated_subject = opts), do: opts
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
            error_description: "Missing or invalid access token.",
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
        %{account: account} = project

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

      %User{} = user ->
        TuistWeb.Authentication.put_current_user(conn, user)

      %AuthenticatedAccount{} = subject ->
        conn
        |> assign(:current_subject, subject)
        |> put_claimed_agent_user(subject)

      nil ->
        conn
    end
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

  defp put_claimed_agent_user(conn, _subject), do: conn
end
