defmodule TuistWeb.MixBuildLive do
  @moduledoc false
  use TuistWeb, :live_view
  use Noora

  import TuistWeb.Runs.ProjectWithTags
  import TuistWeb.Runs.RanByBadge

  alias Tuist.Mix
  alias Tuist.Projects
  alias TuistWeb.Errors.NotFoundError
  alias TuistWeb.Utilities.Query

  @impl true
  def mount(%{"build_id" => build_id}, _session, %{assigns: %{selected_project: project}} = socket) do
    run =
      case Mix.get_build(build_id, project_id: project.id) do
        {:ok, run} ->
          run

        {:error, :not_found} ->
          raise NotFoundError, dgettext("dashboard_builds", "Build not found.")
      end

    run = Tuist.Repo.preload(run, ran_by_account: [])

    slug = Projects.get_project_slug_from_id(project.id)
    diagnostics = Mix.list_diagnostics(run.id)
    machine_metrics = Mix.list_machine_metrics(run.id)

    errors = Enum.filter(diagnostics, &(&1.severity == "error"))
    warnings = Enum.filter(diagnostics, &(&1.severity == "warning"))

    {:ok,
     socket
     |> assign(:run, run)
     |> assign(:diagnostics, diagnostics)
     |> assign(:errors, errors)
     |> assign(:warnings, warnings)
     |> assign(:machine_metrics, machine_metrics)
     |> assign(:selected_tab, "overview")
     |> assign(:head_title, "#{dgettext("dashboard_builds", "Mix Build")} · #{slug} · Tuist")}
  end

  @impl true
  def handle_params(params, uri, socket) do
    parsed = URI.parse(uri)

    {:noreply,
     socket
     |> assign(:uri, parsed)
     |> assign(:selected_tab, Map.get(params, "tab", "overview"))}
  end

  @doc false
  def url?(value) when is_binary(value) do
    case URI.parse(value) do
      %URI{scheme: scheme, host: host} when scheme in ["http", "https"] and is_binary(host) and host != "" -> true
      _ -> false
    end
  end

  def url?(_), do: false

  @doc false
  def diagnostic_group_key(%{file: file}) when is_binary(file) and file != "", do: file
  def diagnostic_group_key(_), do: "(unknown source)"

  @doc false
  def query_put(query, key, value), do: Query.put(query || "", key, value)
end
