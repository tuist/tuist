defmodule TuistWeb.API.Authorization.AuthorizationPlug do
  @moduledoc ~S"""
  A plug that authorizes API actions.
  """
  use TuistWeb, :controller

  alias Tuist.Authorization
  alias TuistWeb.Authentication

  def init(:run), do: :run
  def init(:bundle), do: :bundle
  def init(:cache), do: :cache
  def init(:preview), do: :preview
  def init(:test), do: :test
  def init(:build), do: :build
  def init(:automation_alert), do: :automation_alert

  def init(opts) when is_list(opts) do
    opts
  end

  @project_categories [:run, :bundle, :cache, :preview, :test, :build, :automation_alert]

  def call(conn, category) when category in @project_categories do
    authorize_project(conn, category)
  end

  def call(conn, opts) do
    :cache = Keyword.fetch!(opts, :category)
    authorize_project(conn, :cache, opts)
  end

  def authorize_project(%{assigns: %{selected_project: selected_project}} = conn, category, opts \\ []) do
    caching = Keyword.get(opts, :caching, false)
    action = get_action(conn)
    subject = Authentication.authenticated_subject(conn)

    cache_key = [
      Atom.to_string(__MODULE__),
      "authorize",
      Atom.to_string(category),
      Atom.to_string(action),
      "#{subject_kind(subject)}-#{subject_id(subject)}",
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
        message: "#{subject_name(subject)} is not authorized to #{Atom.to_string(action)} #{Atom.to_string(category)}"
      })
      |> halt()
    end
  end

  defp subject_kind(%{__struct__: struct}), do: Atom.to_string(struct)
  defp subject_kind(_subject), do: "unknown"

  defp subject_id(%{id: id}), do: id
  defp subject_id(%{account: %{id: id}}), do: id
  defp subject_id(_subject), do: "unknown"

  defp subject_name(%{account: %{name: name}}), do: name
  defp subject_name(_subject), do: "The authenticated subject"

  def authorize(subject, action, project, category) do
    category
    |> authorization_action(action)
    |> Authorization.authorize(subject, project)
    |> Kernel.==(:ok)
  end

  defp authorization_action(:cache, action), do: authorization_action(:project, :"cache_#{action}")
  defp authorization_action(category, action), do: :"#{category}_#{action}"

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
