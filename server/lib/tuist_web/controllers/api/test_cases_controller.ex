defmodule TuistWeb.API.TestCasesController do
  use OpenApiSpex.ControllerSpecs
  use TuistWeb, :controller

  alias OpenApiSpex.Schema
  alias Tuist.Runs
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

    {test_cases, meta} = Runs.list_test_cases(selected_project.id, options)

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

  defp build_filters(params) do
    filters = []

    filters =
      if Map.get(params, :flaky) do
        filters ++ [%{field: :is_flaky, op: :==, value: true}]
      else
        filters
      end

    if Map.get(params, :quarantined) do
      filters ++ [%{field: :is_quarantined, op: :==, value: true}]
    else
      filters
    end
  end

  defp build_suite(nil), do: nil
  defp build_suite(""), do: nil
  defp build_suite(suite_name), do: %{id: suite_name, name: suite_name}
end
