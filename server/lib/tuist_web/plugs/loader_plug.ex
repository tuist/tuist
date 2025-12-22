defmodule TuistWeb.Plugs.LoaderPlug do
  @moduledoc ~S"""
  This plug is responsible for loading (and caching) the resources pointed by the path or body parameters.
  """
  use TuistWeb, :controller
  use TuistWeb, :verified_routes

  alias Tuist.Accounts
  alias Tuist.CommandEvents
  alias Tuist.Projects
  alias TuistWeb.Errors.BadRequestError
  alias TuistWeb.Errors.NotFoundError
  alias TuistWeb.Plugs.AppsignalAttributionPlug

  def init([]), do: [:project, :account, :run]
  def init(opts), do: opts

  def call(
        %{path_params: %{"run_id" => run_id, "account_handle" => account_handle, "project_handle" => project_name}} = conn,
        opts
      ) do
    conn
    |> then(
      &if :project in opts,
        do: assign_selected_project(&1, "#{account_handle}/#{project_name}"),
        else: &1
    )
    |> then(
      &if :run in opts,
        do: load_run(&1, run_id),
        else: &1
    )
  end

  def call(%{path_params: %{"run_id" => run_id}} = conn, opts) do
    then(conn, &if(:run in opts, do: load_run(&1, run_id), else: &1))
  end

  def call(%{path_params: %{"account_handle" => account_handle, "project_handle" => project_name}} = conn, _opts) do
    assign_selected_project(conn, "#{account_handle}/#{project_name}")
  end

  def call(%{params: %{"account_handle" => account_handle}} = conn, _opts) do
    account =
      cached(conn, ["account", account_handle], fn ->
        Accounts.get_account_by_handle(account_handle)
      end)

    case account do
      nil ->
        raise NotFoundError,
              dgettext("dashboard", "The account %{account_handle} was not found.", %{
                account_handle: account_handle
              })

      account ->
        conn
        |> assign(:selected_account, account)
        |> AppsignalAttributionPlug.set_selection_tags()
    end
  end

  def call(%{body_params: %{project_id: project_slug}} = conn, _opts) do
    assign_selected_project(conn, project_slug)
  end

  def call(%{query_params: %{"project_id" => project_slug}} = conn, _opts) do
    assign_selected_project(conn, project_slug)
  end

  def call(conn, _opts) do
    conn
  end

  defp load_run(conn, run_id) do
    run_result =
      cached(conn, ["run", run_id], fn ->
        CommandEvents.get_command_event_by_id(run_id)
      end)

    case run_result do
      {:ok, run} ->
        {:ok, project} = CommandEvents.get_project_for_command_event(run, preload: :account)

        conn
        |> assign(:selected_account, project.account)
        |> assign(:selected_project, project)
        |> assign(:selected_run, run)
        |> AppsignalAttributionPlug.set_selection_tags()

      {:error, :not_found} ->
        raise NotFoundError,
              dgettext("dashboard", "The run with ID %{run_id} was not found.", %{run_id: run_id})
    end
  end

  def assign_selected_project(conn, project_slug) do
    project =
      cached(conn, ["project", project_slug], fn ->
        Projects.get_project_by_slug(project_slug, preload: [:account])
      end)

    case project do
      {:ok, project} ->
        conn
        |> assign(:selected_project, project)
        |> assign(:selected_account, project.account)
        |> AppsignalAttributionPlug.set_selection_tags()

      {:error, :not_found} ->
        raise NotFoundError,
              dgettext("dashboard", "The project %{project_slug} was not found.", %{project_slug: project_slug})

      {:error, :invalid} ->
        raise BadRequestError,
              dgettext(
                "dashboard",
                "The project full handle %{project_slug} is invalid. It should follow the convention 'account_handle/project_handle'.",
                %{
                  project_slug: project_slug
                }
              )
    end
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
      cache: cache,
      locking: true
    ]

    if Map.get(conn.assigns, :caching, true) do
      Tuist.KeyValueStore.get_or_update(cache_key, cache_opts, fetch_value)
    else
      fetch_value.()
    end
  end
end
