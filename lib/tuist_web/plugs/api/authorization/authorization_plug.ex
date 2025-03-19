defmodule TuistWeb.API.Authorization.AuthorizationPlug do
  @moduledoc ~S"""
  A plug that authorizes API actions.
  """
  use TuistWeb, :controller
  use TuistWeb, :verified_routes

  alias Tuist.Authorization
  alias TuistWeb.Authentication
  alias TuistWeb.API.EnsureProjectPresencePlug

  def init(:run), do: :run
  def init(:cache), do: :cache
  def init(:preview), do: :preview
  def init(:registry), do: :registry

  def init(opts) when is_list(opts) do
    opts
  end

  def call(conn, category) when is_atom(category) do
    case category do
      :run ->
        authorize_project(conn, :run)

      :cache ->
        authorize_project(conn, :cache)

      :preview ->
        authorize_project(conn, :preview)

      :registry ->
        authorize_account(conn, :registry)
    end
  end

  def call(conn, opts) do
    case Keyword.fetch!(opts, :category) do
      :cache ->
        authorize_project(conn, :cache, opts)
    end
  end

  defp authorize_account(%{assigns: %{url_account: url_account}} = conn, category) do
    action = get_action(conn)

    subject =
      Authentication.authenticated_subject(conn)

    if authorize(subject, action, url_account, category) do
      conn
    else
      status =
        case category do
          :registry -> :unauthorized
          _ -> :forbidden
        end

      conn
      |> put_status(status)
      |> json(%{
        message: "You are not authorized to #{Atom.to_string(action)} #{Atom.to_string(category)}"
      })
      |> halt()
    end
  end

  def authorize_project(conn, category, opts \\ []) do
    caching = Keyword.get(opts, :caching, false)
    action = get_action(conn)

    project =
      EnsureProjectPresencePlug.get_project(conn)

    subject =
      Authentication.authenticated_subject(conn)

    cache_key = [
      "authorize",
      "#{Atom.to_string(subject.__struct__)}-#{subject.id}",
      "#{Atom.to_string(project.__struct__)}-#{project.id}",
      "cache"
    ]

    authorized? =
      if caching do
        cached(
          cache_key,
          fn -> authorize(subject, action, project, category) end,
          opts |> Keyword.put(:cache, Map.get(conn.assigns, :cache, :tuist))
        )
      else
        authorize(subject, action, project, category)
      end

    if authorized? do
      conn
    else
      conn
      |> put_status(:forbidden)
      |> json(%{
        message:
          "#{subject.account.name} is not authorized to #{Atom.to_string(action)} #{Atom.to_string(category)}"
      })
      |> halt()
    end
  end

  def cached(cache_key, func, opts) do
    cache = Keyword.fetch!(opts, :cache)
    cache_ttl = Keyword.get(opts, :cache_ttl, :timer.minutes(1))

    Cachex.transaction!(cache, cache_key, fn cache ->
      {:ok, cached_value} = Cachex.get(cache, cache_key)

      if is_nil(cached_value) do
        value = func.()
        Cachex.put(cache, cache_key, value, ttl: cache_ttl)
        value
      else
        cached_value
      end
    end)
  end

  def authorize(subject, :read, project, :cache) do
    Authorization.can?(:project_cache_read, subject, project)
  end

  def authorize(subject, :read, account, :registry) do
    Authorization.can?(:account_registry_read, subject, account)
  end

  def authorize(subject, :create, account, :registry) do
    # Logging in is done via POST request
    Authorization.can?(:account_registry_read, subject, account)
  end

  def authorize(subject, :create, account, :account_token) do
    Authorization.can?(:account_token_create, subject, account)
  end

  def authorize(subject, :create, project, :run) do
    Authorization.can?(:project_run_create, subject, project)
  end

  def authorize(subject, :read, project, :run) do
    Authorization.can?(:project_run_read, subject, project)
  end

  def authorize(subject, :update, project, :run) do
    Authorization.can?(:project_run_update, subject, project)
  end

  def authorize(subject, action, project, category) do
    Authorization.can(subject, action, project, category)
  end

  defp get_action(conn) do
    case conn.method do
      "POST" -> :create
      "GET" -> :read
      "PUT" -> :update
      "DELETE" -> :delete
    end
  end
end
