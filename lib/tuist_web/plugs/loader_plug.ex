defmodule TuistWeb.Plugs.LoaderPlug do
  @moduledoc ~S"""
  This plug is responsible for loading (and caching) the resources pointed by the path or body parameters.
  """
  use TuistWeb, :controller
  use TuistWeb, :verified_routes
  alias Tuist.Projects
  alias Tuist.CommandEvents
  alias TuistWeb.Errors.NotFoundError

  def init(opts), do: opts

  def call(
        %{
          path_params: %{
            "run_id" => run_id
          }
        } = conn,
        opts
      ) do
    cache_ttl = Map.get(conn.assigns, :cache_ttl, :timer.minutes(1))
    cache = Map.get(conn.assigns, :cache, :tuist)

    cache_key = [
      Atom.to_string(__MODULE__),
      "run",
      run_id
    ]

    cache_opts = [
      ttl: cache_ttl,
      cache: cache
    ]

    fetch_run = fn ->
      CommandEvents.get_command_event_by_id(run_id,
        preload: [user: :account, project: :account]
      )
    end

    run =
      if Map.get(conn.assigns, :caching, true) do
        Tuist.Cache.get_value(cache_key, cache_opts, fetch_run)
      else
        fetch_run.()
      end

    if is_nil(run) do
      raise NotFoundError, gettext("The run with ID %{run_id} was not found.", %{run_id: run_id})
    else
      conn
      |> assign(:selected_account, run.project.account)
      |> assign(:selected_project, run.project)
      |> assign(:selected_run, run)
    end
  end

  def call(
        %{
          path_params: %{
            "account_handle" => account_handle,
            "project_handle" => project_name
          }
        } = conn,
        _opts
      ) do
    project_slug = "#{account_handle}/#{project_name}"

    fetch_project = fn ->
      Projects.get_project_by_slug(project_slug, preload: [:account])
    end

    project =
      case Map.get(conn.assigns, :caching, true) do
        true ->
          Tuist.Cache.get_value(
            [Atom.to_string(__MODULE__), "project", project_slug],
            [
              ttl: Map.get(conn.assigns, :cache_ttl, :timer.minutes(1)),
              cache: Map.get(conn.assigns, :cache, :tuist)
            ],
            fetch_project
          )

        false ->
          fetch_project.()
      end

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

  def call(conn, opts) do
    conn
  end
end
