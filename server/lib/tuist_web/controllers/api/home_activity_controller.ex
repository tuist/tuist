defmodule TuistWeb.API.HomeActivityController do
  use OpenApiSpex.ControllerSpecs
  use TuistWeb, :controller

  alias Tuist.HomeActivity
  alias TuistWeb.API.Authorization.AuthorizationPlug
  alias TuistWeb.API.Responses
  alias TuistWeb.API.Schemas.Error
  alias TuistWeb.API.Schemas.HomeActivity, as: HomeActivitySchema

  plug(TuistWeb.Plugs.CastAndValidate,
    json_render_error_v2: true,
    render_error: TuistWeb.RenderAPIErrorPlug
  )

  plug(TuistWeb.Plugs.LoaderPlug)
  plug(AuthorizationPlug, :build when action in [:build_failures])
  plug(AuthorizationPlug, :test when action in [:test_failures, :flaky_tests])

  tags(["Home"])

  @parameters [
    account_handle: [in: :path, type: :string, required: true],
    project_handle: [in: :path, type: :string, required: true]
  ]
  @responses %{
    ok: {"Recent project activity", "application/json", HomeActivitySchema},
    forbidden: {"You don't have permission to access this resource", "application/json", Error},
    unprocessable_entity: {"This build system is not supported by this section", "application/json", Error},
    too_many_requests: Responses.authorization_throttled()
  }

  operation(:build_failures,
    operation_id: "getHomeBuildFailures",
    summary: "Latest three failed builds from the last seven days.",
    parameters: @parameters,
    responses: @responses
  )

  operation(:test_failures,
    operation_id: "getHomeTestFailures",
    summary: "Latest three failed test runs from the last seven days.",
    parameters: @parameters,
    responses: @responses
  )

  operation(:flaky_tests,
    operation_id: "getHomeFlakyTests",
    summary: "Latest three currently flaky tests marked flaky in the last seven days.",
    parameters: @parameters,
    responses: @responses
  )

  def build_failures(conn, _params), do: render_activity(conn, :build_failures)
  def test_failures(conn, _params), do: render_activity(conn, :test_failures)
  def flaky_tests(conn, _params), do: render_activity(conn, :flaky_tests)

  defp render_activity(%{assigns: %{selected_project: project}} = conn, kind) do
    conn = put_resp_header(conn, "cache-control", "private, no-store")

    case apply(HomeActivity, kind, [project]) do
      {:ok, items} ->
        json(conn, %{items: Enum.map(items, &Map.put(&1, :url, destination(project, kind, &1.id)))})

      {:error, :unsupported} ->
        conn
        |> put_status(:unprocessable_entity)
        |> json(%{message: "This activity section is not available for this project's build system yet."})
    end
  end

  defp destination(project, :build_failures, id) do
    case project.build_system do
      :once -> path(%URI{}, ~p"/#{project.account.name}/#{project.name}/once/runs/#{id}")
      :bazel -> path(%URI{}, ~p"/#{project.account.name}/#{project.name}/builds/invocations/#{id}")
      _ -> path(%URI{}, ~p"/#{project.account.name}/#{project.name}/builds/build-runs/#{id}")
    end
  end

  defp destination(project, :test_failures, id),
    do: path(%URI{}, ~p"/#{project.account.name}/#{project.name}/tests/test-runs/#{id}")

  defp destination(project, :flaky_tests, id),
    do: path(%URI{}, ~p"/#{project.account.name}/#{project.name}/tests/test-cases/#{id}")
end
