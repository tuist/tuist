defmodule TuistWeb.API.TestCaseRunsController do
  use OpenApiSpex.ControllerSpecs
  use TuistWeb, :controller

  alias OpenApiSpex.Schema
  alias Tuist.Tests
  alias TuistWeb.API.Schemas.Error
  alias TuistWeb.API.Schemas.PaginationMetadata

  plug(OpenApiSpex.Plug.CastAndValidate,
    json_render_error_v2: true,
    render_error: TuistWeb.RenderAPIErrorPlug
  )

  plug(TuistWeb.Plugs.LoaderPlug)
  plug(TuistWeb.API.Authorization.AuthorizationPlug, :test)

  tags ["Test Case Runs"]

  operation(:index,
    summary: "List runs for a test case.",
    operation_id: "listTestCaseRuns",
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
      ],
      flaky: [
        in: :query,
        type: :boolean,
        description: "Filter by flaky status. When true, only returns flaky runs."
      ],
      page_size: [
        in: :query,
        type: %Schema{
          title: "TestCaseRunsIndexPageSize",
          description: "The maximum number of test case runs to return in a single page.",
          type: :integer,
          default: 20,
          minimum: 1,
          maximum: 500
        }
      ],
      page: [
        in: :query,
        type: %Schema{
          title: "TestCaseRunsIndexPage",
          description: "The page number to return.",
          type: :integer,
          default: 1,
          minimum: 1
        }
      ]
    ],
    responses: %{
      ok:
        {"List of test case runs", "application/json",
         %Schema{
           type: :object,
           properties: %{
             test_case_runs: %Schema{
               type: :array,
               items: %Schema{
                 type: :object,
                 properties: %{
                   id: %Schema{type: :string, format: :uuid, description: "The test case run ID."},
                   status: %Schema{type: :string, enum: ["success", "failure", "skipped"], description: "Run status."},
                   duration: %Schema{type: :integer, description: "Duration in milliseconds."},
                   is_ci: %Schema{type: :boolean, description: "Whether the run was on CI."},
                   is_flaky: %Schema{type: :boolean, description: "Whether the run was flaky."},
                   is_new: %Schema{type: :boolean, description: "Whether this was a new test case."},
                   scheme: %Schema{type: :string, nullable: true, description: "Build scheme."},
                   git_branch: %Schema{type: :string, nullable: true, description: "Git branch."},
                   git_commit_sha: %Schema{type: :string, nullable: true, description: "Git commit SHA."},
                   ran_at: %Schema{
                     type: :string,
                     format: :"date-time",
                     nullable: true,
                     description: "ISO 8601 timestamp when the run executed."
                   }
                 },
                 required: [:id, :status, :duration, :is_ci, :is_flaky, :is_new]
               }
             },
             pagination_metadata: PaginationMetadata
           },
           required: [:test_case_runs, :pagination_metadata]
         }},
      forbidden: {"You don't have permission to access this resource", "application/json", Error}
    }
  )

  def index(
        %{
          assigns: %{selected_project: _selected_project},
          params: %{test_case_id: test_case_id, page_size: page_size, page: page} = params
        } = conn,
        _params
      ) do
    filters = build_run_filters(params)

    options = %{
      filters: filters,
      order_by: [:ran_at],
      order_directions: [:desc],
      page: page,
      page_size: page_size
    }

    {runs, meta} = Tests.list_test_case_runs_by_test_case_id(test_case_id, options)

    json(conn, %{
      test_case_runs:
        Enum.map(runs, fn run ->
          %{
            id: run.id,
            status: to_string(run.status),
            duration: run.duration,
            is_ci: run.is_ci,
            is_flaky: run.is_flaky,
            is_new: run.is_new,
            scheme: run.scheme,
            git_branch: run.git_branch,
            git_commit_sha: run.git_commit_sha,
            ran_at: format_ran_at(run.ran_at)
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
    summary: "Get a test case run by ID.",
    operation_id: "getTestCaseRun",
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
      test_case_run_id: [
        in: :path,
        schema: %Schema{type: :string, format: :uuid},
        required: true,
        description: "The ID of the test case run."
      ]
    ],
    responses: %{
      ok:
        {"Test case run details", "application/json",
         %Schema{
           type: :object,
           properties: %{
             id: %Schema{type: :string, format: :uuid, description: "The test case run ID."},
             test_case_id: %Schema{type: :string, format: :uuid, nullable: true, description: "The test case ID."},
             test_run_id: %Schema{type: :string, format: :uuid, nullable: true, description: "The test run ID."},
             name: %Schema{type: :string, description: "Name of the test case."},
             module_name: %Schema{type: :string, description: "Module name."},
             suite_name: %Schema{type: :string, nullable: true, description: "Suite name."},
             status: %Schema{type: :string, enum: ["success", "failure", "skipped"], description: "Run status."},
             duration: %Schema{type: :integer, description: "Duration in milliseconds."},
             is_ci: %Schema{type: :boolean, description: "Whether the run was on CI."},
             is_flaky: %Schema{type: :boolean, description: "Whether the run was flaky."},
             is_new: %Schema{type: :boolean, description: "Whether this was a new test case."},
             scheme: %Schema{type: :string, nullable: true, description: "Build scheme."},
             git_branch: %Schema{type: :string, nullable: true, description: "Git branch."},
             git_commit_sha: %Schema{type: :string, nullable: true, description: "Git commit SHA."},
             ran_at: %Schema{
               type: :string,
               format: :"date-time",
               nullable: true,
               description: "ISO 8601 timestamp when the run executed."
             },
             failures: %Schema{
               type: :array,
               items: %Schema{
                 type: :object,
                 properties: %{
                   message: %Schema{type: :string, description: "Failure message."},
                   path: %Schema{type: :string, nullable: true, description: "File path."},
                   line_number: %Schema{type: :integer, nullable: true, description: "Line number."},
                   issue_type: %Schema{type: :string, nullable: true, description: "Type of issue."}
                 },
                 required: [:message]
               }
             },
             repetitions: %Schema{
               type: :array,
               items: %Schema{
                 type: :object,
                 properties: %{
                   repetition_number: %Schema{type: :integer, description: "Repetition number."},
                   status: %Schema{
                     type: :string,
                     enum: ["success", "failure", "skipped"],
                     description: "Repetition status."
                   },
                   duration: %Schema{type: :integer, description: "Duration in milliseconds."}
                 },
                 required: [:repetition_number, :status, :duration]
               }
             }
           },
           required: [
             :id,
             :name,
             :module_name,
             :status,
             :duration,
             :is_ci,
             :is_flaky,
             :is_new,
             :failures,
             :repetitions
           ]
         }},
      not_found: {"Test case run not found", "application/json", Error},
      forbidden: {"You don't have permission to access this resource", "application/json", Error}
    }
  )

  def show(
        %{assigns: %{selected_project: selected_project}, params: %{test_case_run_id: test_case_run_id}} = conn,
        _params
      ) do
    case Tests.get_test_case_run_by_id(test_case_run_id, preload: [:failures, :repetitions]) do
      {:ok, run} ->
        if run.project_id == selected_project.id do
          json(conn, %{
            id: run.id,
            test_case_id: run.test_case_id,
            test_run_id: run.test_run_id,
            name: run.name,
            module_name: run.module_name,
            suite_name: run.suite_name,
            status: to_string(run.status),
            duration: run.duration,
            is_ci: run.is_ci,
            is_flaky: run.is_flaky,
            is_new: run.is_new,
            scheme: run.scheme,
            git_branch: run.git_branch,
            git_commit_sha: run.git_commit_sha,
            ran_at: format_ran_at(run.ran_at),
            failures:
              Enum.map(run.failures, fn f ->
                %{
                  message: f.message,
                  path: f.path,
                  line_number: f.line_number,
                  issue_type: f.issue_type
                }
              end),
            repetitions:
              Enum.map(run.repetitions, fn r ->
                %{
                  repetition_number: r.repetition_number,
                  status: to_string(r.status),
                  duration: r.duration
                }
              end)
          })
        else
          conn
          |> put_status(:not_found)
          |> json(%{message: "Test case run not found."})
        end

      {:error, :not_found} ->
        conn
        |> put_status(:not_found)
        |> json(%{message: "Test case run not found."})
    end
  end

  defp format_ran_at(nil), do: nil

  defp format_ran_at(%NaiveDateTime{} = ran_at) do
    ran_at |> NaiveDateTime.truncate(:second) |> DateTime.from_naive!("Etc/UTC") |> DateTime.to_iso8601()
  end

  defp format_ran_at(%DateTime{} = ran_at), do: DateTime.to_iso8601(ran_at)

  defp build_run_filters(params) do
    if Map.get(params, :flaky) do
      [%{field: :is_flaky, op: :==, value: true}]
    else
      []
    end
  end
end
