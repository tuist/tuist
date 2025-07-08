defmodule TuistWeb.ProjectTestsLive do
  @moduledoc false
  use TuistWeb, :live_view

  alias Tuist.CommandEvents
  alias Tuist.Projects
  alias Tuist.Projects.Project
  alias TuistWeb.Flop

  def mount(params, _session, %{assigns: %{selected_project: project}} = socket) do
    uri = URI.new!("?" <> URI.encode_query(Map.take(params, ["after", "before"])))

    {flaky_tests, flaky_tests_meta} = list_flaky_tests(project)
    slug = Projects.get_project_slug_from_id(project.id)

    {
      :ok,
      socket
      |> assign(:uri, uri)
      |> assign(:head_title, "#{gettext("Tests")} · #{slug} · Tuist")
      |> assign(:flaky_tests, flaky_tests)
      |> assign(:flaky_tests_meta, flaky_tests_meta)
    }
  end

  def handle_params(params, _uri, %{assigns: %{selected_project: project}} = socket) do
    {next_flaky_tests, next_flaky_tests_meta} =
      list_flaky_tests(project, before: params["before"], after: params["after"])

    {
      :noreply,
      socket
      |> assign(:flaky_tests, next_flaky_tests)
      |> assign(:flaky_tests_meta, next_flaky_tests_meta)
    }
  end

  defp list_flaky_tests(%Project{} = project, attrs \\ []) do
    options =
      Flop.get_options_with_before_and_after(
        %{order_by: [:last_flaky_test_case_run_inserted_at], order_directions: [:desc]},
        attrs
      )

    CommandEvents.list_flaky_test_cases(project, options)
  end
end
