defmodule TuistWeb.AuthenticationPlug do
  @moduledoc """
  A plug that deals with authentication of requests.
  """
  use TuistWeb, :controller

  import Plug.Conn

  alias Tuist.Accounts.AuthenticatedAccount
  alias Tuist.Accounts.User
  alias Tuist.Projects
  alias Tuist.Projects.Project
  alias TuistWeb.Headers
  alias TuistWeb.WarningsHeaderPlug

  def init(:load_authenticated_subject = opts), do: opts
  def init({:require_authentication, _} = opts), do: opts

  def call(conn, :load_authenticated_subject) do
    token = TuistWeb.Authentication.get_authorization_token_from_conn(conn)

    if token do
      get_authenticated_subject(conn, token)
    else
      conn
    end
  end

  def call(conn, {:require_authentication, opts}) do
    response_type = Keyword.get(opts, :response_type, :open_api)

    if TuistWeb.Authentication.authenticated?(conn) do
      conn
    else
      :open_api = response_type

      conn
      |> put_status(:unauthorized)
      |> json(%{message: "You need to be authenticated to access this resource."})
      |> halt()
    end
  end

  defp get_authenticated_subject(conn, token) do
    cache_key = [Atom.to_string(__MODULE__), "authenticated_subject", token]

    cache_opts = [
      ttl: Map.get(conn.assigns, :cache_ttl, to_timeout(minute: 1)),
      cache: Map.get(conn.assigns, :cache, :tuist),
      locking: true
    ]

    get_authenticated_subject = fn ->
      Tuist.Authentication.authenticated_subject(token)
    end

    authenticated_subject =
      if Map.get(conn.assigns, :caching, false) do
        Tuist.KeyValueStore.get_or_update(cache_key, cache_opts, get_authenticated_subject)
      else
        get_authenticated_subject.()
      end

    case authenticated_subject do
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

      %AuthenticatedAccount{} = authenticated_account ->
        assign(conn, :current_subject, authenticated_account)

      nil ->
        conn
    end
  end
end
