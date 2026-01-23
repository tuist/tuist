defmodule TuistWeb.API.TestCasesController do
  use OpenApiSpex.ControllerSpecs
  use TuistWeb, :controller

  alias OpenApiSpex.Schema
  alias Tuist.Runs
  alias TuistWeb.API.Schemas.Error
  alias TuistWeb.API.Schemas.TestCaseRead

  plug(OpenApiSpex.Plug.CastAndValidate,
    json_render_error_v2: true,
    render_error: TuistWeb.RenderAPIErrorPlug
  )

  plug(TuistWeb.Plugs.LoaderPlug)
  plug(TuistWeb.API.Authorization.AuthorizationPlug, :test_case)

  tags(["TestCases"])

  operation(:index,
    summary: "List test cases for a project.",
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
      name: [
        in: :query,
        type: :string,
        description: "The name of the test case."
      ],
      module_name: [
        in: :query,
        type: :string,
        description: "The module name of the test case."
      ],
      suite_name: [
        in: :query,
        type: :string,
        description: "The suite name of the test case."
      ],
      status: [
        in: :query,
        type: :string,
        description: "The last status of the test case."
      ],
      page_size: [
        in: :query,
        type: %Schema{
          title: "TestCasesIndexPageSize",
          description: "The maximum number of test cases to return in a single page.",
          type: :integer,
          default: 20,
          minimum: 1,
          maximum: 100
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
               items: TestCaseRead
             }
           },
           required: [:test_cases]
         }},
      unauthorized: {"You need to be authenticated to access this resource", "application/json", Error},
      forbidden: {"You don't have permission to access this resource", "application/json", Error}
    }
  )

  def index(
        %{assigns: %{selected_project: selected_project}, params: %{page_size: page_size, page: page} = params} = conn,
        _params
      ) do
    filters = filters_from_params(params)

    {test_cases, _meta} =
      Runs.list_test_cases(selected_project.id, %{
        page: page,
        page_size: page_size,
        filters: filters,
        order_by: [:last_ran_at],
        order_directions: [:desc]
      })

    json(conn, %{
      test_cases: Enum.map(test_cases, &test_case_to_map(&1, selected_project))
    })
  end

  operation(:show,
    summary: "Get a single test case by ID.",
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
        type: :string,
        required: true,
        description: "The ID of the test case."
      ]
    ],
    responses: %{
      ok: {"Test case details", "application/json", TestCaseRead},
      unauthorized: {"You need to be authenticated to access this resource", "application/json", Error},
      not_found: {"Test case not found", "application/json", Error},
      forbidden: {"You don't have permission to access this resource", "application/json", Error}
    }
  )

  def show(%{assigns: %{selected_project: selected_project}} = conn, params) do
    test_case_id = params[:test_case_id]

    case Runs.get_test_case(test_case_id) do
      {:error, :not_found} ->
        conn
        |> put_status(:not_found)
        |> json(%{message: "Test case not found"})

      {:ok, test_case} ->
        if test_case.project_id == selected_project.id do
          json(conn, test_case_to_map(test_case, selected_project))
        else
          conn
          |> put_status(:not_found)
          |> json(%{message: "Test case not found"})
        end
    end
  end

  defp filters_from_params(params) do
    []
    |> maybe_add_filter(:name, params[:name])
    |> maybe_add_filter(:module_name, params[:module_name])
    |> maybe_add_filter(:suite_name, params[:suite_name])
    |> maybe_add_filter(:last_status, params[:status])
  end

  defp maybe_add_filter(filters, _field, nil), do: filters
  defp maybe_add_filter(filters, field, value), do: [%{field: field, op: :==, value: value} | filters]

  defp test_case_to_map(test_case, selected_project) do
    %{
      id: test_case.id,
      name: test_case.name,
      module_name: test_case.module_name,
      suite_name: test_case.suite_name,
      last_status: test_case.last_status,
      last_duration: test_case.last_duration,
      last_ran_at: to_unix(test_case.last_ran_at),
      avg_duration: test_case.avg_duration,
      url: ~p"/#{selected_project.account.name}/#{selected_project.name}/tests/test-cases/#{test_case.id}"
    }
  end

  defp to_unix(%DateTime{} = datetime), do: DateTime.to_unix(datetime)
  defp to_unix(%NaiveDateTime{} = datetime), do: datetime |> DateTime.from_naive!("Etc/UTC") |> DateTime.to_unix()
end
