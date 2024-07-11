defmodule TuistCloudWeb.ProjectTestsLive do
  alias TuistCloudWeb.Flop
  alias TuistCloud.Projects
  alias TuistCloud.Projects.Project
  alias TuistCloud.CommandEvents
  use TuistCloudWeb, :live_view

  def mount(params, _session, %{assigns: %{selected_project: project}} = socket) do
    uri =
      ("?" <> URI.encode_query(Map.take(params, ["after", "before"])))
      |> URI.new!()

    {flaky_tests, flaky_tests_meta} = list_flaky_tests(project)
    slug = Projects.get_project_slug_from_id(project.id)

    {
      :ok,
      socket
      |> assign(:uri, uri)
      |> assign(:page_title, "#{gettext("Tests")} · #{slug} · Tuist")
      |> assign(:flaky_tests, flaky_tests)
      |> assign(:flaky_tests_meta, flaky_tests_meta)
    }
  end

  def handle_params(
        params,
        _uri,
        %{assigns: %{selected_project: project}} = socket
      ) do
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
      %{
        order_by: [:last_flaky_test_case_run_inserted_at],
        order_directions: [:desc]
      }
      |> Flop.get_options_with_before_and_after(attrs)

    CommandEvents.list_flaky_test_cases(project, options)
  end
end
