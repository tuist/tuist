defmodule TuistWeb.API.SelectiveTestingController do
  @moduledoc """
  A test run's coverage-based selection: the tests it decided and the files
  that changed since its baseline. Both read empty when the run had no such
  selection.
  """
  use OpenApiSpex.ControllerSpecs
  use TuistWeb, :controller

  alias OpenApiSpex.Schema
  alias Tuist.Tests
  alias Tuist.Tests.Selections.Query, as: SelectionQuery
  alias Tuist.Tests.Selections.Schemas, as: SelectionSchemas
  alias TuistWeb.API.Responses
  alias TuistWeb.API.Schemas.Error
  alias TuistWeb.API.Schemas.PaginationMetadata

  plug(TuistWeb.Plugs.CastAndValidate,
    json_render_error_v2: true,
    render_error: TuistWeb.RenderAPIErrorPlug
  )

  plug(TuistWeb.Plugs.LoaderPlug)
  plug(TuistWeb.API.Authorization.AuthorizationPlug, :test)

  tags ["Tests"]

  @path_parameters [
    account_handle: [in: :path, type: :string, required: true, description: "The handle of the account."],
    project_handle: [in: :path, type: :string, required: true, description: "The handle of the project."],
    test_run_id: [
      in: :path,
      schema: %Schema{type: :string, format: :uuid},
      required: true,
      description: "The ID of the test run."
    ]
  ]

  @page_parameters (for {prefix, noun} <- [{"SelectiveTestingTests", "tests"}, {"SelectiveTestingChangedFiles", "files"}],
                        into: %{} do
                      {prefix,
                       [
                         page: [
                           in: :query,
                           type: %Schema{
                             title: "#{prefix}Page",
                             description: "The page number to return.",
                             type: :integer,
                             default: 1,
                             minimum: 1
                           }
                         ],
                         page_size: [
                           in: :query,
                           type: %Schema{
                             title: "#{prefix}PageSize",
                             description: "The maximum number of #{noun} to return in a single page.",
                             type: :integer,
                             default: 20,
                             minimum: 1,
                             maximum: 100
                           }
                         ]
                       ]}
                    end)

  operation(:tests,
    summary: "List the tests a test run's coverage-based selection decided.",
    description:
      "Every test the selection was asked about, selected and skipped, with the reason for each decision, the changed file that selected it, its shard and its outcome in this run. Empty when the run had no coverage-based selection.",
    operation_id: "listTestRunSelectiveTestingTests",
    parameters:
      @path_parameters ++
        [
          decision: [
            in: :query,
            type: %Schema{title: "SelectiveTestingDecision", type: :string, enum: ["selected", "skipped"]},
            description: "Only the selected or only the skipped tests."
          ],
          reason: [
            in: :query,
            type: :string,
            description: "Only the tests with this reason, such as `impacted`, `unaffected` or `tracked_file_changed`."
          ],
          search: [in: :query, type: :string, description: "Part of the module, suite or test name."]
        ] ++ @page_parameters["SelectiveTestingTests"],
    responses: %{
      ok: {"The run's selection tests", "application/json", SelectionSchemas.tests(PaginationMetadata)},
      not_found: {"Test run not found", "application/json", Error},
      forbidden: {"You don't have permission to access this resource", "application/json", Error},
      too_many_requests: Responses.authorization_throttled()
    }
  )

  def tests(%{assigns: %{selected_project: project}, params: %{test_run_id: test_run_id} = params} = conn, _params) do
    with_test_run(conn, project, test_run_id, fn test_run ->
      SelectionQuery.tests(test_run,
        decision: Map.get(params, :decision),
        reason: Map.get(params, :reason),
        search: Map.get(params, :search),
        page: params.page,
        page_size: params.page_size
      )
    end)
  end

  operation(:changed_files,
    summary: "List the files that changed since a test run's selection baseline.",
    description:
      "The files coverage-based selection compared against its baseline, the ones that selected the most tests first, each with whether it's a tracked file whose change makes selection fall back. Empty when the run had no baseline, ran from a dirty checkout whose client didn't mark its uncommitted changes, or its diff expired. For a dirty checkout, only its uncommitted changes are listed.",
    operation_id: "listTestRunSelectiveTestingChangedFiles",
    parameters:
      @path_parameters ++
        [search: [in: :query, type: :string, description: "Part of the file's path."]] ++
        @page_parameters["SelectiveTestingChangedFiles"],
    responses: %{
      ok: {"The run's changed files", "application/json", SelectionSchemas.changed_files(PaginationMetadata)},
      not_found: {"Test run not found", "application/json", Error},
      forbidden: {"You don't have permission to access this resource", "application/json", Error},
      too_many_requests: Responses.authorization_throttled()
    }
  )

  def changed_files(
        %{assigns: %{selected_project: project}, params: %{test_run_id: test_run_id} = params} = conn,
        _params
      ) do
    with_test_run(conn, project, test_run_id, fn test_run ->
      SelectionQuery.changed_files(project, test_run,
        search: Map.get(params, :search),
        page: params.page,
        page_size: params.page_size
      )
    end)
  end

  defp with_test_run(conn, project, test_run_id, read) do
    case Tests.get_test(test_run_id) do
      {:ok, %{project_id: project_id} = test_run} when project_id == project.id ->
        {:ok, page} = read.(test_run)
        json(conn, page)

      _ ->
        conn
        |> put_status(:not_found)
        |> json(%{message: "Test run not found."})
    end
  end
end
