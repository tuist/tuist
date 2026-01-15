defmodule TuistWeb.API.TestsController do
  use OpenApiSpex.ControllerSpecs
  use TuistWeb, :controller

  alias OpenApiSpex.Schema
  alias Tuist.Runs
  alias TuistWeb.API.Schemas.Error
  alias TuistWeb.API.Schemas.TestRunRead

  plug(OpenApiSpex.Plug.CastAndValidate,
    json_render_error_v2: true,
    render_error: TuistWeb.RenderAPIErrorPlug
  )

  plug(TuistWeb.Plugs.LoaderPlug)
  plug(TuistWeb.API.Authorization.AuthorizationPlug, :test)

  tags(["Tests"])

  operation(:index,
    summary: "List test runs for a project.",
    operation_id: "listTests",
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
      status: [
        in: :query,
        type: :string,
        description: "The status of the test run."
      ],
      scheme: [
        in: :query,
        type: :string,
        description: "The scheme used for the test run."
      ],
      git_ref: [
        in: :query,
        type: :string,
        description: "The git ref of the test run."
      ],
      git_branch: [
        in: :query,
        type: :string,
        description: "The git branch of the test run."
      ],
      git_commit_sha: [
        in: :query,
        type: :string,
        description: "The git commit SHA of the test run."
      ],
      page_size: [
        in: :query,
        type: %Schema{
          title: "TestsIndexPageSize",
          description: "The maximum number of tests to return in a single page.",
          type: :integer,
          default: 20,
          minimum: 1,
          maximum: 100
        }
      ],
      page: [
        in: :query,
        type: %Schema{
          title: "TestsIndexPage",
          description: "The page number to return.",
          type: :integer,
          default: 1,
          minimum: 1
        }
      ]
    ],
    responses: %{
      ok:
        {"List of tests", "application/json",
         %Schema{
           type: :object,
           properties: %{
             tests: %Schema{
               type: :array,
               items: TestRunRead
             }
           },
           required: [:tests]
         }},
      unauthorized: {"You need to be authenticated to access this resource", "application/json", Error},
      forbidden: {"You don't have permission to access this resource", "application/json", Error}
    }
  )

  def index(
        %{assigns: %{selected_project: selected_project}, params: %{page_size: page_size, page: page} = params} = conn,
        _params
      ) do
    filters =
      [
        %{field: :project_id, op: :==, value: selected_project.id}
      ] ++ filters_from_params(params)

    {tests, _meta} =
      Runs.list_test_runs(%{
        page: page,
        page_size: page_size,
        filters: filters,
        order_by: [:ran_at],
        order_directions: [:desc]
      })

    json(conn, %{
      tests: Enum.map(tests, &test_to_map(&1, selected_project))
    })
  end

  operation(:show,
    summary: "Get a single test run by ID.",
    operation_id: "getTest",
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
      test_id: [
        in: :path,
        type: :string,
        required: true,
        description: "The ID of the test run."
      ]
    ],
    responses: %{
      ok: {"Test details", "application/json", TestRunRead},
      unauthorized: {"You need to be authenticated to access this resource", "application/json", Error},
      not_found: {"Test not found", "application/json", Error},
      forbidden: {"You don't have permission to access this resource", "application/json", Error}
    }
  )

  def show(%{assigns: %{selected_project: selected_project}} = conn, params) do
    test_id = params[:test_id]

    case Runs.get_test(test_id, preload: [:ran_by_account]) do
      {:error, :not_found} ->
        conn
        |> put_status(:not_found)
        |> json(%{message: "Test not found"})

      {:ok, test} ->
        if test.project_id == selected_project.id do
          json(conn, test_to_map(test, selected_project))
        else
          conn
          |> put_status(:not_found)
          |> json(%{message: "Test not found"})
        end
    end
  end

  defp filters_from_params(params) do
    []
    |> maybe_add_filter(:status, params[:status])
    |> maybe_add_filter(:scheme, params[:scheme])
    |> maybe_add_filter(:git_ref, params[:git_ref])
    |> maybe_add_filter(:git_branch, params[:git_branch])
    |> maybe_add_filter(:git_commit_sha, params[:git_commit_sha])
  end

  defp maybe_add_filter(filters, _field, nil), do: filters
  defp maybe_add_filter(filters, field, value), do: [%{field: field, op: :==, value: value} | filters]

  defp test_to_map(test, selected_project) do
    ran_by =
      case test.ran_by_account do
        nil -> nil
        account -> %{handle: account.name}
      end

    %{
      id: test.id,
      duration: test.duration,
      status: test.status,
      scheme: test.scheme,
      git_branch: test.git_branch,
      git_commit_sha: test.git_commit_sha,
      git_ref: test.git_ref,
      is_ci: test.is_ci,
      xcode_version: test.xcode_version,
      macos_version: test.macos_version,
      model_identifier: test.model_identifier,
      build_run_id: test.build_run_id,
      url: ~p"/#{selected_project.account.name}/#{selected_project.name}/tests/test-runs/#{test.id}",
      ran_at: to_unix(test.ran_at),
      ran_by: ran_by
    }
  end

  defp to_unix(%DateTime{} = datetime), do: DateTime.to_unix(datetime)
  defp to_unix(%NaiveDateTime{} = datetime), do: datetime |> DateTime.from_naive!("Etc/UTC") |> DateTime.to_unix()
end
