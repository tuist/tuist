defmodule TuistWeb.API.NotRunTestsController do
  use OpenApiSpex.ControllerSpecs
  use TuistWeb, :controller

  alias OpenApiSpex.Schema
  alias Tuist.Tests
  alias Tuist.Tests.Enumeration
  alias TuistWeb.API.Responses
  alias TuistWeb.API.Schemas.Error

  plug(TuistWeb.Plugs.CastAndValidate,
    json_render_error_v2: true,
    render_error: TuistWeb.RenderAPIErrorPlug
  )

  plug(TuistWeb.Plugs.LoaderPlug)
  plug(TuistWeb.API.Authorization.AuthorizationPlug, :test)
  plug(TuistWeb.Plugs.RequireCoveragePlug)

  tags ["Tests"]

  operation(:index,
    summary: "List the tests a test run could have executed and left out.",
    description:
      "The client lists a run's candidate tests without running any; the run's filters do not narrow the list. This is the enabled candidates with no result in the run: what a selective run skipped.",
    operation_id: "listTestRunNotRunTests",
    parameters: [
      account_handle: [in: :path, type: :string, required: true, description: "The handle of the account."],
      project_handle: [in: :path, type: :string, required: true, description: "The handle of the project."],
      test_run_id: [
        in: :path,
        schema: %Schema{type: :string, format: :uuid},
        required: true,
        description: "The ID of the test run."
      ],
      page: [
        in: :query,
        type: %Schema{title: "NotRunTestsPage", type: :integer, default: 1, minimum: 1},
        description: "The page number to return."
      ],
      page_size: [
        in: :query,
        type: %Schema{title: "NotRunTestsPageSize", type: :integer, default: 50, minimum: 1, maximum: 500},
        description: "The maximum number of tests to return in a single page."
      ]
    ],
    responses: %{
      ok:
        {"The tests the run left out", "application/json",
         %Schema{
           title: "TestRunNotRunTests",
           type: :object,
           properties: %{
             enumerated_test_count: %Schema{type: :integer, description: "Tests the run could have executed."},
             enabled_test_count: %Schema{type: :integer, description: "Those the scheme or test plan enables."},
             not_run_test_count: %Schema{type: :integer, description: "Enabled tests the run left out."},
             tests: %Schema{
               type: :array,
               items: %Schema{
                 type: :object,
                 properties: %{
                   test_case_id: %Schema{type: :string, format: :uuid},
                   module_name: %Schema{type: :string},
                   suite_name: %Schema{type: :string},
                   name: %Schema{type: :string}
                 },
                 required: [:test_case_id, :module_name, :suite_name, :name]
               }
             }
           },
           required: [:enumerated_test_count, :enabled_test_count, :not_run_test_count, :tests]
         }},
      not_found: {"Test run not found, or its tests were not enumerated", "application/json", Error},
      forbidden: {"You don't have permission to access this resource", "application/json", Error},
      too_many_requests: Responses.authorization_throttled()
    }
  )

  def index(%{assigns: %{selected_project: project}, params: %{test_run_id: test_run_id} = params} = conn, _params) do
    with {:ok, %{project_id: project_id} = run} when project_id == project.id <- Tests.get_test(test_run_id),
         %{} = summary <- Enumeration.summary(run) do
      tests = Enumeration.list_not_run(run, page: Map.get(params, :page, 1), page_size: Map.get(params, :page_size, 50))
      json(conn, Enumeration.payload(summary, tests))
    else
      _ ->
        conn
        |> put_status(:not_found)
        |> json(%{message: "Test run not found, or its tests were not enumerated."})
    end
  end
end
