defmodule TuistWeb.API.Authorization.AuthorizationPlug do
  @moduledoc ~S"""
  A plug that authorizes API actions.
  """
  use TuistWeb, :controller
  use TuistWeb, :verified_routes

  alias Tuist.Authorization
  alias TuistWeb.Authentication

  def init(:run), do: :run
  def init(:bundle), do: :bundle
  def init(:cache), do: :cache
  def init(:preview), do: :preview
  def init(:registry), do: :registry
  def init(:qa_run), do: :qa_run
  def init(:qa_step), do: :qa_step
  def init(:qa_screenshot), do: :qa_screenshot

  def init(opts) when is_list(opts) do
    opts
  end

  def call(conn, category) when is_atom(category) do
    case category do
      :run ->
        authorize_project(conn, :run)

      :bundle ->
        authorize_project(conn, :bundle)

      :cache ->
        authorize_project(conn, :cache)

      :preview ->
        authorize_project(conn, :preview)

      :registry ->
        authorize_account(conn, :registry)

      :qa_run ->
        authorize_project(conn, :qa_run)

      :qa_step ->
        authorize_project(conn, :qa_step)

      :qa_screenshot ->
        authorize_project(conn, :qa_screenshot)
    end
  end

  def call(conn, opts) do
    :cache = Keyword.fetch!(opts, :category)
    authorize_project(conn, :cache, opts)
  end

  defp authorize_account(%{assigns: assigns} = conn, :registry) when not is_map_key(assigns, :selected_account) do
    conn
  end

  defp authorize_account(%{assigns: %{selected_account: selected_account}} = conn, category) do
    action = get_action(conn)

    subject =
      Authentication.authenticated_subject(conn)

    if authorize(subject, action, selected_account, category) do
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

  def authorize_project(%{assigns: %{selected_project: selected_project}} = conn, category, opts \\ []) do
    caching = Keyword.get(opts, :caching, false)
    action = get_action(conn)
    subject = Authentication.authenticated_subject(conn)

    subject_id =
      case subject do
        %{id: id} -> id
        %{account: %{id: id}} -> id
      end

    cache_key = [
      Atom.to_string(__MODULE__),
      "authorize",
      "#{Atom.to_string(subject.__struct__)}-#{subject_id}",
      "#{Atom.to_string(selected_project.__struct__)}-#{selected_project.id}"
    ]

    authorized? =
      if caching do
        Tuist.KeyValueStore.get_or_update(
          cache_key,
          [
            cache: Map.get(conn.assigns, :cache, :tuist),
            ttl: Keyword.get(opts, :cache_ttl, to_timeout(minute: 1)),
            locking: true
          ],
          fn ->
            authorize(subject, action, selected_project, category)
          end
        )
      else
        authorize(subject, action, selected_project, category)
      end

    if authorized? do
      conn
    else
      conn
      |> put_status(:forbidden)
      |> json(%{
        message: "#{subject.account.name} is not authorized to #{Atom.to_string(action)} #{Atom.to_string(category)}"
      })
      |> halt()
    end
  end

  def authorize(subject, action, project, category) do
    Authorization.authorize(:"#{category}_#{action}", subject, project) == :ok
  end

  defp get_action(conn) do
    case conn.method do
      "POST" -> :create
      "GET" -> :read
      "PUT" -> :update
      "PATCH" -> :update
      "DELETE" -> :delete
    end
  end
end
