defmodule TuistWeb.API.TestSuiteRunsController do
  use OpenApiSpex.ControllerSpecs
  use TuistWeb, :controller

  alias OpenApiSpex.Schema
  alias Tuist.Tests
  alias TuistWeb.API.Schemas.Error
  alias TuistWeb.API.Schemas.PaginationMetadata

  plug(TuistWeb.Plugs.InstrumentedCastAndValidate,
    json_render_error_v2: true,
    render_error: TuistWeb.RenderAPIErrorPlug
  )

  plug(TuistWeb.Plugs.LoaderPlug)
  plug(TuistWeb.API.Authorization.AuthorizationPlug, :test)

  tags ["Tests"]

  operation(:index,
    summary: "List test suite runs for a test run.",
    operation_id: "listTestSuiteRuns",
    parameters: [
      account_handle: [
        in: :path,
        type: :string,
        required: true,
        description: "The handle of the account."
      ],
      project_handle: [
        in: :path,
        type: :string,
        required: true,
        description: "The handle of the project."
      ],
      test_run_id: [
        in: :path,
        schema: %Schema{type: :string, format: :uuid},
        required: true,
        description: "The ID of the test run."
      ],
      module_name: [
        in: :query,
        type: :string,
        description: "Filter by module name."
      ],
      status: [
        in: :query,
        type: %Schema{
          title: "TestSuiteRunStatus",
          type: :string,
          enum: ["success", "failure", "skipped"]
        },
        description: "Filter by suite run status."
      ],
      page: [
        in: :query,
        type: %Schema{
          title: "TestSuiteRunsPage",
          description: "The page number to return.",
          type: :integer,
          default: 1,
          minimum: 1
        }
      ],
      page_size: [
        in: :query,
        type: %Schema{
          title: "TestSuiteRunsPageSize",
          description: "The maximum number of suite runs to return in a single page.",
          type: :integer,
          default: 20,
          minimum: 1,
          maximum: 100
        }
      ]
    ],
    responses: %{
      ok:
        {"List of test suite runs", "application/json",
         %Schema{
           type: :object,
           properties: %{
             suites: %Schema{
               type: :array,
               items: %Schema{
                 type: :object,
                 properties: %{
                   name: %Schema{type: :string, description: "The suite name."},
                   status: %Schema{type: :string, enum: ["success", "failure", "skipped"], description: "Suite status."},
                   is_flaky: %Schema{type: :boolean, description: "Whether the suite had flaky tests."},
                   duration: %Schema{type: :integer, description: "Duration in milliseconds."},
                   test_case_count: %Schema{type: :integer, description: "Number of test cases."},
                   avg_test_case_duration: %Schema{
                     type: :integer,
                     description: "Average test case duration in milliseconds."
                   }
                 },
                 required: [:name, :status, :duration]
               }
             },
             pagination_metadata: PaginationMetadata
           },
           required: [:suites, :pagination_metadata]
         }},
      not_found: {"Test run not found", "application/json", Error},
      forbidden: {"You don't have permission to access this resource", "application/json", Error}
    }
  )

  def index(
        %{assigns: %{selected_project: selected_project}, params: %{test_run_id: test_run_id} = params} = conn,
        _params
      ) do
    case Tests.get_test(test_run_id) do
      {:ok, %{project_id: project_id}} when project_id == selected_project.id ->
        page = Map.get(params, :page, 1)
        page_size = Map.get(params, :page_size, 20)

        filters = [%{field: :test_run_id, op: :==, value: test_run_id}]

        filters =
          if Map.get(params, :status) do
            filters ++ [%{field: :status, op: :==, value: params.status}]
          else
            filters
          end

        filters =
          case Map.get(params, :module_name) do
            nil ->
              filters

            module_name ->
              module_filters = [
                %{field: :test_run_id, op: :==, value: test_run_id},
                %{field: :name, op: :==, value: module_name}
              ]

              {module_runs, _meta} =
                Tests.list_test_module_runs(%{
                  filters: module_filters,
                  page: 1,
                  page_size: 100
                })

              module_run_ids = Enum.map(module_runs, & &1.id)

              if module_run_ids == [] do
                filters ++ [%{field: :test_module_run_id, op: :==, value: nil}]
              else
                filters ++ [%{field: :test_module_run_id, op: :in, value: module_run_ids}]
              end
          end

        attrs = %{
          filters: filters,
          order_by: [:duration],
          order_directions: [:desc],
          page: page,
          page_size: page_size
        }

        {suites, meta} = Tests.list_test_suite_runs(attrs)

        json(conn, %{
          suites:
            Enum.map(suites, fn suite ->
              %{
                name: suite.name,
                status: to_string(suite.status),
                is_flaky: suite.is_flaky,
                duration: suite.duration,
                test_case_count: suite.test_case_count,
                avg_test_case_duration: suite.avg_test_case_duration
              }
            end),
          pagination_metadata: %{
            has_next_page: meta.has_next_page?,
            has_previous_page: meta.has_previous_page?,
            current_page: meta.current_page,
            page_size: meta.page_size,
            total_count: meta.total_count,
            total_pages: meta.total_pages
          }
        })

      _error ->
        conn
        |> put_status(:not_found)
        |> json(%{message: "Test run not found."})
    end
  end
end
