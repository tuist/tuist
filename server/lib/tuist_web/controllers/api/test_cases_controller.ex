defmodule TuistWeb.API.TestCasesController do
  use OpenApiSpex.ControllerSpecs
  use TuistWeb, :controller

  alias OpenApiSpex.Schema
  alias Tuist.Tests
  alias Tuist.Tests.Analytics
  alias TuistWeb.API.Schemas.Error
  alias TuistWeb.API.Schemas.PaginationMetadata
  alias TuistWeb.API.Schemas.TestCase

  plug(OpenApiSpex.Plug.CastAndValidate,
    json_render_error_v2: true,
    render_error: TuistWeb.RenderAPIErrorPlug
  )

  plug(TuistWeb.Plugs.LoaderPlug)
  plug(TuistWeb.API.Authorization.AuthorizationPlug, :test)

  tags ["Test Cases"]

  operation(:index,
    summary: "List test cases associated with a given project.",
    operation_id: "listTestCases",
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
      flaky: [
        in: :query,
        type: :boolean,
        description: "Filter by flaky status. When true, only returns flaky test cases."
      ],
      quarantined: [
        in: :query,
        type: :boolean,
        description: "Filter by quarantined status. When true, only returns quarantined test cases."
      ],
      module_name: [
        in: :query,
        type: :string,
        description: "Filter by module name. Returns only test cases in the given module."
      ],
      name: [
        in: :query,
        type: :string,
        description: "Filter by test case name."
      ],
      suite_name: [
        in: :query,
        type: :string,
        description: "Filter by suite name."
      ],
      page_size: [
        in: :query,
        type: %Schema{
          title: "TestCasesIndexPageSize",
          description: "The maximum number of test cases to return in a single page.",
          type: :integer,
          default: 20,
          minimum: 1,
          maximum: 500
        }
      ],
      page: [
        in: :query,
        type: %Schema{
          title: "TestCasesIndexPage",
          description: "The page number to return.",
          type: :integer,
          default: 1,
          minimum: 1
        }
      ]
    ],
    responses: %{
      ok:
        {"List of test cases", "application/json",
         %Schema{
           type: :object,
           properties: %{
             test_cases: %Schema{
               type: :array,
               items: TestCase
             },
             pagination_metadata: PaginationMetadata
           },
           required: [:test_cases, :pagination_metadata]
         }},
      forbidden: {"You don't have permission to access this resource", "application/json", Error}
    }
  )

  def index(
        %{assigns: %{selected_project: selected_project}, params: %{page_size: page_size, page: page} = params} = conn,
        _params
      ) do
    filters = build_filters(params)

    options = %{
      filters: filters,
      order_by: [:last_ran_at],
      order_directions: [:desc],
      page: page,
      page_size: page_size
    }

    {test_cases, meta} = Tests.list_test_cases(selected_project.id, options)

    json(conn, %{
      test_cases:
        Enum.map(test_cases, fn test_case ->
          %{
            id: test_case.id,
            name: test_case.name,
            module: %{
              id: test_case.module_name,
              name: test_case.module_name
            },
            suite: build_suite(test_case.suite_name),
            avg_duration: test_case.avg_duration,
            is_flaky: test_case.is_flaky,
            is_quarantined: test_case.is_quarantined,
            url: ~p"/#{selected_project.account.name}/#{selected_project.name}/tests/test-cases/#{test_case.id}"
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
  end

  operation(:show,
    summary: "Get a test case by ID.",
    operation_id: "getTestCase",
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
      test_case_id: [
        in: :path,
        schema: %Schema{type: :string, format: :uuid},
        required: true,
        description: "The ID of the test case."
      ]
    ],
    responses: %{
      ok:
        {"Test case details", "application/json",
         %Schema{
           type: :object,
           properties: %{
             id: %Schema{type: :string, format: :uuid, description: "The test case ID."},
             name: %Schema{type: :string, description: "Name of the test case."},
             module: %Schema{
               type: :object,
               required: [:id, :name],
               properties: %{
                 id: %Schema{type: :string, description: "ID of the module."},
                 name: %Schema{type: :string, description: "Name of the module."}
               }
             },
             suite: %Schema{
               type: :object,
               nullable: true,
               required: [:id, :name],
               properties: %{
                 id: %Schema{type: :string, description: "ID of the suite."},
                 name: %Schema{type: :string, description: "Name of the suite."}
               }
             },
             is_flaky: %Schema{type: :boolean, description: "Whether the test case is marked as flaky."},
             is_quarantined: %Schema{type: :boolean, description: "Whether the test case is quarantined."},
             last_status: %Schema{type: :string, enum: ["success", "failure", "skipped"], description: "Status of the last run."},
             last_duration: %Schema{type: :integer, description: "Duration of the last run in milliseconds."},
             last_ran_at: %Schema{type: :integer, description: "Unix timestamp of when the test case last ran."},
             avg_duration: %Schema{type: :integer, description: "Average duration of recent runs in milliseconds."},
             reliability_rate: %Schema{type: :number, nullable: true, description: "Success rate percentage (0-100)."},
             flakiness_rate: %Schema{type: :number, description: "Flakiness rate percentage (0-100) over last 30 days."},
             total_runs: %Schema{type: :integer, description: "Total number of runs."},
             failed_runs: %Schema{type: :integer, description: "Number of failed runs."},
             url: %Schema{type: :string, description: "URL to view the test case in the dashboard."}
           },
           required: [
             :id,
             :name,
             :module,
             :is_flaky,
             :is_quarantined,
             :last_status,
             :last_duration,
             :last_ran_at,
             :avg_duration,
             :flakiness_rate,
             :total_runs,
             :failed_runs,
             :url
           ]
         }},
      not_found: {"Test case not found", "application/json", Error},
      forbidden: {"You don't have permission to access this resource", "application/json", Error}
    }
  )

  def show(
        %{assigns: %{selected_project: selected_project}, params: %{test_case_id: test_case_id}} = conn,
        _params
      ) do
    case Tests.get_test_case_by_id(test_case_id) do
      {:ok, test_case} ->
        if test_case.project_id == selected_project.id do
          default_branch = selected_project.default_branch || "main"
          analytics = Analytics.test_case_analytics_by_id(test_case_id)
          reliability_rate = Analytics.test_case_reliability_by_id(test_case_id, default_branch)
          flakiness_rate = Analytics.get_test_case_flakiness_rate(test_case)

          json(conn, %{
            id: test_case.id,
            name: test_case.name,
            module: %{
              id: test_case.module_name,
              name: test_case.module_name
            },
            suite: build_suite(test_case.suite_name),
            is_flaky: test_case.is_flaky,
            is_quarantined: test_case.is_quarantined,
            last_status: to_string(test_case.last_status),
            last_duration: test_case.last_duration,
            last_ran_at: test_case.last_ran_at |> DateTime.from_naive!("Etc/UTC") |> DateTime.to_unix(),
            avg_duration: test_case.avg_duration,
            reliability_rate: reliability_rate,
            flakiness_rate: flakiness_rate,
            total_runs: analytics.total_count,
            failed_runs: analytics.failed_count,
            url: ~p"/#{selected_project.account.name}/#{selected_project.name}/tests/test-cases/#{test_case.id}"
          })
        else
          conn
          |> put_status(:not_found)
          |> json(%{message: "Test case not found."})
        end

      {:error, :not_found} ->
        conn
        |> put_status(:not_found)
        |> json(%{message: "Test case not found."})
    end
  end

  defp build_filters(params) do
    []
    |> maybe_add_filter(:is_flaky, Map.get(params, :flaky))
    |> maybe_add_filter(:is_quarantined, Map.get(params, :quarantined))
    |> maybe_add_filter(:module_name, Map.get(params, :module_name))
    |> maybe_add_filter(:name, Map.get(params, :name))
    |> maybe_add_filter(:suite_name, Map.get(params, :suite_name))
  end

  defp maybe_add_filter(filters, _field, nil), do: filters
  defp maybe_add_filter(filters, field, true) when field in [:is_flaky, :is_quarantined], do: filters ++ [%{field: field, op: :==, value: true}]
  defp maybe_add_filter(filters, field, value), do: filters ++ [%{field: field, op: :==, value: value}]

  defp build_suite(nil), do: nil
  defp build_suite(""), do: nil
  defp build_suite(suite_name), do: %{id: suite_name, name: suite_name}
end
