defmodule TuistWeb.Plugs.LoaderPlug do
  @moduledoc ~S"""
  This plug is responsible for loading (and caching) the resources pointed by the path or body parameters.
  """
  use TuistWeb, :controller
  use TuistWeb, :verified_routes

  alias Tuist.Accounts
  alias Tuist.CommandEvents
  alias Tuist.Projects
  alias TuistWeb.Errors.NotFoundError

  def init(opts), do: opts

  def call(%{path_params: %{"run_id" => run_id}} = conn, opts) do
    run =
      cached(conn, ["run", run_id], fn ->
        CommandEvents.get_command_event_by_id(run_id,
          preload: [user: :account, project: :account]
        )
      end)

    if is_nil(run) do
      raise NotFoundError, gettext("The run with ID %{run_id} was not found.", %{run_id: run_id})
    else
      conn
      |> assign(:selected_account, run.project.account)
      |> assign(:selected_project, run.project)
      |> assign(:selected_run, run)
    end
  end

  def call(%{path_params: %{"account_handle" => account_handle, "project_handle" => project_name}} = conn, _opts) do
    project_slug = "#{account_handle}/#{project_name}"

    project =
      cached(conn, ["project", project_slug], fn ->
        Projects.get_project_by_slug(project_slug, preload: [:account])
      end)

    case project do
      {:ok, project} ->
        conn
        |> assign(:selected_project, project)
        |> assign(:selected_account, project.account)

      {:error, :not_found} ->
        raise NotFoundError,
              gettext("The project %{project_slug} was not found.", %{project_slug: project_slug})
    end
  end

  def call(%{params: %{"account_handle" => account_handle}} = conn, _opts) do
    account =
      cached(conn, ["account", account_handle], fn ->
        Accounts.get_account_by_handle(account_handle)
      end)

    case account do
      nil ->
        raise NotFoundError,
              gettext("The account %{account_handle} was not found.", %{
                account_handle: account_handle
              })

      account ->
        assign(conn, :selected_account, account)
    end
  end

  def call(conn, opts) do
    conn
  end

  defp cached(conn, cache_key, fetch_value) do
    cache_ttl = Map.get(conn.assigns, :cache_ttl, to_timeout(minute: 1))
    cache = Map.get(conn.assigns, :cache, :tuist)

    cache_key =
      [
        Atom.to_string(__MODULE__)
      ] ++ cache_key

    cache_opts = [
      ttl: cache_ttl,
      cache: cache
    ]

    if Map.get(conn.assigns, :caching, true) do
      Tuist.Cache.get_value(cache_key, cache_opts, fetch_value)
    else
      fetch_value.()
    end
  end
end
