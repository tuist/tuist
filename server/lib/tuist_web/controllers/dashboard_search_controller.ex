defmodule TuistWeb.DashboardSearchController do
  @moduledoc false
  use TuistWeb, :controller

  alias Tuist.Accounts
  alias Tuist.AppBuilds
  alias Tuist.Authorization
  alias Tuist.DashboardSearch
  alias Tuist.KeyValueStore.LoadLimiter
  alias Tuist.Projects
  alias TuistWeb.DashboardNavigation
  alias TuistWeb.RateLimit

  def child_spec(_opts) do
    LoadLimiter.child_spec(
      name: __MODULE__.Loaders,
      max_concurrency: 2,
      max_pending_loads: 2,
      max_waiters: 1,
      load_timeout: 4_000
    )
  end

  def search(conn, %{"account_handle" => handle} = params) do
    conn = put_resp_header(conn, "cache-control", "private, no-store")
    user = conn.assigns.current_user
    # This JSON pipeline has no LocalePlug. Resolve the locale the way dashboard
    # LiveViews do: the user's preference, then the browser locale the session
    # recorded on page load.
    locale =
      Enum.find_value([user.preferred_locale, get_session(conn, :locale)], &TuistWeb.Locale.normalize_locale/1) ||
        Gettext.get_locale(TuistWeb.Gettext)

    with {:allow, _} <- search_budget("user:#{user.id}", 4, 2),
         {:ok, result} <-
           LoadLimiter.run(__MODULE__.Loaders, make_ref(), fn ->
             Gettext.put_locale(TuistWeb.Gettext, locale)
             search_account(user, handle, params)
           end) do
      case result do
        {:ok, data} -> json(conn, data)
        {:error, status, message} -> conn |> put_status(status) |> json(%{message: message})
        {:deny, retry} -> throttled(conn, retry)
        {:error, :unavailable} -> unavailable(conn)
      end
    else
      {:deny, retry} -> throttled(conn, retry)
      {:error, :overloaded} -> throttled(conn, 1_000)
      {:error, _} -> unavailable(conn)
    end
  end

  defp search_budget(subject, capacity, refill_rate) do
    RateLimit.hit("dashboard-search:#{subject}",
      algorithm: :token_bucket,
      capacity: capacity,
      refill_rate: refill_rate,
      fallback: false
    )
  end

  defp throttled(conn, retry) do
    conn
    |> put_resp_header("retry-after", to_string(max(1, ceil(retry / 1_000))))
    |> put_status(:too_many_requests)
    |> json(%{message: "Search is busy. Please try again shortly."})
  end

  defp unavailable(conn) do
    conn |> put_status(:service_unavailable) |> json(%{message: "Search is temporarily unavailable."})
  end

  defp search_account(user, handle, params) do
    account = Accounts.get_account_by_handle(handle)
    query = Map.get(params, "search_query", "")

    cond do
      is_nil(account) or Authorization.authorize(:account_dashboard_read, user, account) != :ok ->
        {:error, :not_found, "Not found"}

      not is_binary(query) or byte_size(query) > 640 or String.length(query) > 160 ->
        {:error, :bad_request, "Invalid search"}

      true ->
        with {:allow, _} <- search_budget("account:#{account.id}", 10, 5) do
          search_projects(user, account, params, query)
        end
    end
  end

  defp search_projects(user, account, params, query) do
    # Account membership is identical for every project. Resolve it once,
    # using fresh data on every request, just as LayoutLive does.
    member? = Accounts.owns_account_or_is_member_of_account_organization?(user, %{id: account.id})
    opts = if member?, do: [], else: [visibility: :public]
    projects = Projects.list_accessible_projects(account, opts)
    project_name = params["project"]
    preferred = Enum.find(projects, &(&1.name == (project_name || params["recent_project"])))

    if is_nil(preferred) and project_name not in [nil, ""] do
      {:error, :not_found, "Not found"}
    else
      result =
        DashboardSearch.search(projects, query, preferred_project_id: preferred && preferred.id, project: project_name)

      result =
        if params["catalog"] == true do
          Map.merge(result, %{
            projects: project_catalog(user, account, projects),
            preferred_project: preferred && preferred.name
          })
        else
          result
        end

      {:ok, result}
    end
  end

  defp project_catalog(user, account, projects) do
    previews = projects |> AppBuilds.project_ids_with_previews() |> MapSet.new()
    # Project administration depends only on this account's membership, not
    # individual project state. Avoid repeating its membership query per project.
    admin? = Authorization.authorize(:project_update, user, account) == :ok

    projects
    |> Enum.sort_by(& &1.name)
    |> Enum.map(fn project ->
      pages = DashboardNavigation.project_pages(user, account, project, project_admin?: admin?)

      pages =
        if not Enum.any?(pages, &(&1.destination == "/previews")) and MapSet.member?(previews, project.id) do
          pages ++
            [
              %{
                title: dgettext("dashboard", "Previews"),
                path: "/#{account.name}/#{project.name}/previews",
                description: dgettext("dashboard", "App previews"),
                destination: "/previews",
                project: project.name
              }
            ]
        else
          pages
        end

      %{name: project.name, path: "/#{account.name}/#{project.name}", pages: pages}
    end)
  end
end
