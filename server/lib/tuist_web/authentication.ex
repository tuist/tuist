defmodule TuistWeb.Authentication do
  @moduledoc ~s"""
  A module that provides functions for authenticating requests.
  """
  use TuistWeb, :verified_routes

  import Phoenix.Controller
  import Plug.Conn

  alias Phoenix.LiveView
  alias Phoenix.LiveView.Socket
  alias Tuist.Accounts
  alias Tuist.Accounts.AuthenticatedAccount
  alias Tuist.Accounts.User
  alias Tuist.Analytics
  alias Tuist.Authorization
  alias Tuist.Projects
  alias Tuist.Projects.Project

  @current_user_key :current_user
  @current_project_key :current_project
  # Make the remember me cookie valid for 60 days.
  # If you want bump or reduce this value, also change
  # the token expiry itself in UserToken.
  @max_age 60 * 60 * 24 * 60
  @remember_me_cookie "_tuist_web_user_remember_me"
  @remember_me_options [sign: true, max_age: @max_age, same_site: "Lax"]

  def authenticated?(%Plug.Conn{} = conn), do: authenticated?(conn.assigns)

  def authenticated?(assigns) when is_map(assigns),
    do: current_user(assigns) != nil or current_project(assigns) != nil or assigns[:current_subject] != nil

  def current_user(%Plug.Conn{} = conn) do
    current_user(conn.assigns)
  end

  def current_user(%Socket{} = socket) do
    current_user(socket.assigns)
  end

  def current_user(assigns) when is_map(assigns) do
    assigns[@current_user_key]
  end

  def current_project(%Plug.Conn{} = conn), do: current_project(conn.assigns)

  def current_project(assigns) when is_map(assigns), do: assigns[@current_project_key]

  def authenticated_subject(conn) do
    user = current_user(conn)
    project = current_project(conn)
    authenticated_account = conn.assigns[:current_subject]

    cond do
      user -> user
      project -> project
      authenticated_account -> authenticated_account
      true -> nil
    end
  end

  def authenticated_subject_account(conn) do
    case authenticated_subject(conn) do
      %User{account: account} -> account
      %Project{account: account} -> account
      %AuthenticatedAccount{account: account} -> account
    end
  end

  def put_current_user(%Plug.Conn{} = conn, user) do
    assign(conn, @current_user_key, user)
  end

  def put_current_user(%Socket{} = socket, user) do
    Phoenix.Component.assign(socket, @current_user_key, user)
  end

  def put_current_user(assigns, user) when is_map(assigns) do
    Map.put(assigns, @current_user_key, user)
  end

  def put_current_project(%Plug.Conn{} = conn, project) do
    assign(
      conn,
      @current_project_key,
      project
    )
  end

  def put_current_project(%Socket{} = socket, project) do
    Phoenix.Component.assign(
      socket,
      @current_project_key,
      project
    )
  end

  def put_current_project(assigns, project) when is_map(assigns) do
    Map.put(
      assigns,
      @current_project_key,
      project
    )
  end

  def account_token(conn) do
    case get_req_header(conn, "authorization") do
      ["Bearer " <> token] -> Accounts.account_token(token)
      _ -> {:error, :not_found}
    end
  end

  def get_authorization_token_from_conn(conn) do
    case get_req_header(conn, "authorization") do
      ["Bearer " <> token] -> token
      _ -> nil
    end
  end

  @doc """
  Logs the user in.

  It renews the session ID and clears the whole session
  to avoid fixation attacks. See the renew_session
  function to customize this behaviour.

  It also sets a `:live_socket_id` key in the session,
  so LiveView sessions are identified and automatically
  disconnected on log out. The line can be safely removed
  if you are not using LiveView.
  """
  def log_in_user(conn, user, params \\ %{}) do
    token = Accounts.generate_user_session_token(user)
    user_return_to = get_session(conn, :user_return_to)

    Analytics.user_authenticate(user)

    conn
    |> renew_session()
    |> put_token_in_session(token)
    |> maybe_write_remember_me_cookie(token, params)
    |> redirect(to: user_return_to || signed_in_path(user))
    |> halt()
  end

  defp maybe_write_remember_me_cookie(conn, token, %{"remember_me" => "true"}) do
    put_resp_cookie(conn, @remember_me_cookie, token, @remember_me_options)
  end

  defp maybe_write_remember_me_cookie(conn, _token, _params) do
    conn
  end

  # This function renews the session ID and erases the whole
  # session to avoid fixation attacks. If there is any data
  # in the session you may want to preserve after log in/log out,
  # you must explicitly fetch the session data before clearing
  # and then immediately set it after clearing, for example:
  #
  #     defp renew_session(conn) do
  #       preferred_locale = get_session(conn, :preferred_locale)
  #
  #       conn
  #       |> configure_session(renew: true)
  #       |> clear_session()
  #       |> put_session(:preferred_locale, preferred_locale)
  #     end
  #
  defp renew_session(conn) do
    conn
    |> configure_session(renew: true)
    |> clear_session()
  end

  @doc """
  Logs the user out.

  It clears all session data for safety. See renew_session.
  """
  def log_out_user(conn) do
    user_token = get_session(conn, :user_token)
    user_token && Accounts.delete_user_session_token(user_token)

    if live_socket_id = get_session(conn, :live_socket_id) do
      TuistWeb.Endpoint.broadcast(live_socket_id, "disconnect", %{})
    end

    conn
    |> renew_session()
    |> delete_resp_cookie(@remember_me_cookie)
    |> redirect(to: ~p"/")
    |> halt()
  end

  @doc """
  Authenticates the user by looking into the session
  and remember me token.
  """
  def fetch_current_user(conn, _opts) do
    {user_token, conn} = ensure_user_token(conn)
    user = user_token && Accounts.get_user_by_session_token(user_token, preload: [:account])
    assign(conn, :current_user, user)
  end

  defp ensure_user_token(conn) do
    if token = get_session(conn, :user_token) do
      {token, conn}
    else
      conn = fetch_cookies(conn, signed: [@remember_me_cookie])

      if token = conn.cookies[@remember_me_cookie] do
        {token, put_token_in_session(conn, token)}
      else
        {nil, conn}
      end
    end
  end

  @doc """
  Handles mounting and authenticating the current_user in LiveViews.

  ## `on_mount` arguments

    * `:mount_current_user` - Assigns current_user
      to socket assigns based on user_token, or nil if
      there's no user_token or no matching user.

    * `:ensure_authenticated` - Authenticates the user from the session,
      and assigns the current_user to socket assigns based
      on user_token.
      Redirects to login page if there's no logged user.

    * `:redirect_if_user_is_authenticated` - Authenticates the user from the session.
      Redirects to signed_in_path if there's a logged user.

  ## Examples

  Use the `on_mount` lifecycle macro in LiveViews to mount or authenticate
  the current_user:

      defmodule TuistWeb.PageLive do
        use TuistWeb, :live_view

        on_mount {TuistWeb.Authentication, :mount_current_user}
        ...
      end

  Or use the `live_session` of your router to invoke the on_mount callback:

      live_session :authenticated, on_mount: [{TuistWeb.Authentication, :ensure_authenticated}] do
        live "/profile", ProfileLive, :index
      end
  """
  def on_mount(:mount_current_user, _params, session, socket) do
    {:cont, mount_current_user(socket, session)}
  end

  def on_mount(:ensure_authenticated, _params, session, socket) do
    socket = mount_current_user(socket, session)

    if socket.assigns.current_user do
      {:cont, socket}
    else
      socket =
        socket
        |> LiveView.put_flash(:error, "You must log in to access this page.")
        |> LiveView.redirect(to: ~p"/users/log_in")

      {:halt, socket}
    end
  end

  def on_mount(:redirect_if_user_is_authenticated, _params, session, socket) do
    socket = mount_current_user(socket, session)
    user = socket.assigns.current_user

    if is_nil(user) do
      {:cont, socket}
    else
      {:halt, LiveView.redirect(socket, to: signed_in_path(user))}
    end
  end

  def mount_current_user(socket, session) do
    Phoenix.Component.assign_new(socket, :current_user, fn ->
      if user_token = session["user_token"] do
        Accounts.get_user_by_session_token(user_token, preload: [:account])
      end
    end)
  end

  @doc """
  Used for routes that require the user to not be authenticated.
  """
  def redirect_if_user_is_authenticated(conn, _opts) do
    user = current_user(conn)

    if is_nil(user) do
      conn
    else
      conn
      |> redirect(to: signed_in_path(user))
      |> halt()
    end
  end

  @doc """
  Used for routes that require the user to be authenticated.

  If you want to enforce the user email is confirmed before
  they use the application at all, here would be a good place.
  """
  def require_authenticated_user(conn, _opts) do
    if TuistWeb.Authentication.authenticated?(conn) do
      conn
    else
      conn
      |> maybe_store_return_to()
      |> redirect(to: ~p"/users/log_in")
      |> halt()
    end
  end

  def require_authenticated_user_for_private_projects(
        %{path_params: %{"account_handle" => account_handle, "project_handle" => project_handle}} = conn,
        opts
      ) do
    project = Projects.get_project_by_account_and_project_handles(account_handle, project_handle)

    if is_nil(project) or Authorization.authorize(:dashboard_read, nil, project) != :ok,
      do: require_authenticated_user(conn, opts),
      else: conn
  end

  def require_authenticated_user_for_previews(%{path_params: %{"id" => preview_id}} = conn, opts) do
    case Tuist.AppBuilds.preview_by_id(preview_id, preload: :project) do
      {:error, _} ->
        require_authenticated_user(conn, opts)

      {:ok, preview} ->
        if (preview.visibility || preview.project.default_previews_visibility) == :public or
             Authorization.authorize(
               :preview_read,
               nil,
               preview.project
             ) == :ok do
          conn
        else
          require_authenticated_user(conn, opts)
        end
    end
  end

  defp put_token_in_session(conn, token) do
    conn
    |> put_session(:user_token, token)
    |> put_session(:live_socket_id, "users_sessions:#{Base.url_encode64(token)}")
  end

  defp maybe_store_return_to(%{method: "GET"} = conn) do
    put_session(conn, :user_return_to, current_path(conn))
  end

  defp maybe_store_return_to(conn), do: conn

  def signed_in_path(user) do
    project =
      if is_nil(user.last_visited_project_id) do
        user |> Projects.get_all_project_accounts() |> List.first()
      else
        Projects.get_project_account_by_project_id(user.last_visited_project_id)
      end

    if project do
      "/#{project.handle}"
    else
      "/#{user.account.name}/projects"
    end
  end
end
