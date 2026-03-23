defmodule TuistWeb.API.TestModuleRunsController do
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
    summary: "List test module runs for a test run.",
    operation_id: "listTestModuleRuns",
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
      status: [
        in: :query,
        type: %Schema{
          title: "TestModuleRunStatus",
          type: :string,
          enum: ["success", "failure"]
        },
        description: "Filter by module run status."
      ],
      page: [
        in: :query,
        type: %Schema{
          title: "TestModuleRunsPage",
          description: "The page number to return.",
          type: :integer,
          default: 1,
          minimum: 1
        }
      ],
      page_size: [
        in: :query,
        type: %Schema{
          title: "TestModuleRunsPageSize",
          description: "The maximum number of module runs to return in a single page.",
          type: :integer,
          default: 20,
          minimum: 1,
          maximum: 100
        }
      ]
    ],
    responses: %{
      ok:
        {"List of test module runs", "application/json",
         %Schema{
           type: :object,
           properties: %{
             modules: %Schema{
               type: :array,
               items: %Schema{
                 type: :object,
                 properties: %{
                   name: %Schema{type: :string, description: "The module name."},
                   status: %Schema{type: :string, enum: ["success", "failure"], description: "Module status."},
                   is_flaky: %Schema{type: :boolean, description: "Whether the module had flaky tests."},
                   duration: %Schema{type: :integer, description: "Duration in milliseconds."},
                   test_suite_count: %Schema{type: :integer, description: "Number of test suites."},
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
           required: [:modules, :pagination_metadata]
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

        attrs = %{
          filters: filters,
          order_by: [:duration],
          order_directions: [:desc],
          page: page,
          page_size: page_size
        }

        {modules, meta} = Tests.list_test_module_runs(attrs)

        json(conn, %{
          modules:
            Enum.map(modules, fn mod ->
              %{
                name: mod.name,
                status: to_string(mod.status),
                is_flaky: mod.is_flaky,
                duration: mod.duration,
                test_suite_count: mod.test_suite_count,
                test_case_count: mod.test_case_count,
                avg_test_case_duration: mod.avg_test_case_duration
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
