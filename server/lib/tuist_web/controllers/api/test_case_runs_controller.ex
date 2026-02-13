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

  @test_case_run_list_item_schema %Schema{
    type: :object,
    properties: %{
      id: %Schema{type: :string, format: :uuid, description: "The test case run ID."},
      name: %Schema{type: :string, description: "Name of the test case."},
      module_name: %Schema{type: :string, description: "Module name."},
      suite_name: %Schema{type: :string, nullable: true, description: "Suite name."},
      status: %Schema{
        type: :string,
        enum: ["success", "failure", "skipped"],
        description: "Run status."
      },
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
    required: [:id, :name, :module_name, :status, :duration, :is_ci, :is_flaky, :is_new]
  }

  @test_case_runs_list_response %Schema{
    type: :object,
    properties: %{
      test_case_runs: %Schema{type: :array, items: @test_case_run_list_item_schema},
      pagination_metadata: PaginationMetadata
    },
    required: [:test_case_runs, :pagination_metadata]
  }

  # --- New consolidated endpoint ---

  operation(:index,
    summary: "List test case runs.",
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
        in: :query,
        schema: %Schema{type: :string, format: :uuid},
        description: "Filter by test case ID."
      ],
      flaky: [
        in: :query,
        type: :boolean,
        description: "Filter by flaky status. When true, only returns flaky runs."
      ],
      test_run_id: [
        in: :query,
        schema: %Schema{type: :string, format: :uuid},
        description: "Filter by test run ID."
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
      ok: {"List of test case runs", "application/json", @test_case_runs_list_response},
      bad_request:
        {"At least one of test_case_id or test_run_id is required", "application/json", Error},
      forbidden:
        {"You don't have permission to access this resource", "application/json", Error}
    }
  )

  def index(
        %{
          assigns: %{selected_project: _selected_project},
          params: %{page_size: page_size, page: page} = params
        } = conn,
        _params
      ) do
    filters = build_run_filters(params)

    if Enum.empty?(filters) do
      conn
      |> put_status(:bad_request)
      |> json(%{message: "At least one of test_case_id or test_run_id is required."})
    else
      render_test_case_runs(conn, filters, page, page_size)
    end
  end

  # --- Deprecated legacy endpoints ---

  operation(:index_by_test_case,
    summary: "List runs for a test case. Deprecated: use listTestCaseRuns with test_case_id query param instead.",
    deprecated: true,
    operation_id: "listTestCaseRunsByTestCase",
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
      test_run_id: [
        in: :query,
        schema: %Schema{type: :string, format: :uuid},
        description: "Filter by test run ID."
      ],
      page_size: [
        in: :query,
        type: %Schema{
          title: "TestCaseRunsByTestCasePageSize",
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
          title: "TestCaseRunsByTestCasePage",
          description: "The page number to return.",
          type: :integer,
          default: 1,
          minimum: 1
        }
      ]
    ],
    responses: %{
      ok: {"List of test case runs", "application/json", @test_case_runs_list_response},
      forbidden:
        {"You don't have permission to access this resource", "application/json", Error}
    }
  )

  def index_by_test_case(
        %{
          assigns: %{selected_project: _selected_project},
          params: %{test_case_id: test_case_id, page_size: page_size, page: page} = params
        } = conn,
        _params
      ) do
    filters =
      [%{field: :test_case_id, op: :==, value: test_case_id} | build_run_filters(params)]

    render_test_case_runs(conn, filters, page, page_size)
  end

  operation(:index_by_test_run,
    summary: "List test case runs for a test run. Deprecated: use listTestCaseRuns with test_run_id query param instead.",
    deprecated: true,
    operation_id: "listTestCaseRunsByTestRun",
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
      page_size: [
        in: :query,
        type: %Schema{
          title: "TestCaseRunsByTestRunPageSize",
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
          title: "TestCaseRunsByTestRunPage",
          description: "The page number to return.",
          type: :integer,
          default: 1,
          minimum: 1
        }
      ]
    ],
    responses: %{
      ok:
        {"List of test case runs for a test run", "application/json",
         @test_case_runs_list_response},
      forbidden:
        {"You don't have permission to access this resource", "application/json", Error}
    }
  )

  def index_by_test_run(
        %{
          assigns: %{selected_project: _selected_project},
          params: %{test_run_id: test_run_id, page_size: page_size, page: page}
        } = conn,
        _params
      ) do
    filters = [%{field: :test_run_id, op: :==, value: test_run_id}]

    render_test_case_runs(conn, filters, page, page_size)
  end

  # --- Show ---

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
             test_case_id: %Schema{
               type: :string,
               format: :uuid,
               nullable: true,
               description: "The test case ID."
             },
             test_run_id: %Schema{
               type: :string,
               format: :uuid,
               nullable: true,
               description: "The test run ID."
             },
             name: %Schema{type: :string, description: "Name of the test case."},
             module_name: %Schema{type: :string, description: "Module name."},
             suite_name: %Schema{type: :string, nullable: true, description: "Suite name."},
             status: %Schema{
               type: :string,
               enum: ["success", "failure", "skipped"],
               description: "Run status."
             },
             duration: %Schema{type: :integer, description: "Duration in milliseconds."},
             is_ci: %Schema{type: :boolean, description: "Whether the run was on CI."},
             is_flaky: %Schema{type: :boolean, description: "Whether the run was flaky."},
             is_new: %Schema{type: :boolean, description: "Whether this was a new test case."},
             scheme: %Schema{type: :string, nullable: true, description: "Build scheme."},
             git_branch: %Schema{type: :string, nullable: true, description: "Git branch."},
             git_commit_sha: %Schema{
               type: :string,
               nullable: true,
               description: "Git commit SHA."
             },
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
                   line_number: %Schema{
                     type: :integer,
                     nullable: true,
                     description: "Line number."
                   },
                   issue_type: %Schema{
                     type: :string,
                     nullable: true,
                     description: "Type of issue."
                   }
                 },
                 required: [:message]
               }
             },
             repetitions: %Schema{
               type: :array,
               items: %Schema{
                 type: :object,
                 properties: %{
                   repetition_number: %Schema{
                     type: :integer,
                     description: "Repetition number."
                   },
                   status: %Schema{
                     type: :string,
                     enum: ["success", "failure", "skipped"],
                     description: "Repetition status."
                   },
                   duration: %Schema{
                     type: :integer,
                     description: "Duration in milliseconds."
                   }
                 },
                 required: [:repetition_number, :status, :duration]
               }
             },
             stack_trace: %Schema{
               type: :object,
               nullable: true,
               description: "Crash stack trace associated with this test case run.",
               properties: %{
                 id: %Schema{
                   type: :string,
                   format: :uuid,
                   description: "The stack trace ID."
                 },
                 file_name: %Schema{
                   type: :string,
                   description: "The crash log file name."
                 },
                 app_name: %Schema{
                   type: :string,
                   nullable: true,
                   description: "The app name."
                 },
                 os_version: %Schema{
                   type: :string,
                   nullable: true,
                   description: "The OS version."
                 },
                 exception_type: %Schema{
                   type: :string,
                   nullable: true,
                   description: "The exception type (e.g., EXC_CRASH)."
                 },
                 signal: %Schema{
                   type: :string,
                   nullable: true,
                   description: "The signal (e.g., SIGABRT)."
                 },
                 exception_subtype: %Schema{
                   type: :string,
                   nullable: true,
                   description: "The exception subtype."
                 },
                 formatted_frames: %Schema{
                   type: :string,
                   nullable: true,
                   description: "Human-readable formatted crash thread frames."
                 }
               },
               required: [:id, :file_name]
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
      forbidden:
        {"You don't have permission to access this resource", "application/json", Error}
    }
  )

  def show(
        %{
          assigns: %{selected_project: selected_project},
          params: %{test_case_run_id: test_case_run_id}
        } = conn,
        _params
      ) do
    case Tests.get_test_case_run_by_id(test_case_run_id, preload: [:failures, :repetitions]) do
      {:ok, run} ->
        if run.project_id == selected_project.id do
          stack_trace = fetch_stack_trace(run.stack_trace_id)

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
              end),
            stack_trace: stack_trace
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

  # --- Private helpers ---

  defp render_test_case_runs(conn, filters, page, page_size) do
    options = %{
      filters: filters,
      order_by: [:ran_at],
      order_directions: [:desc],
      page: page,
      page_size: page_size
    }

    {runs, meta} = Tests.list_test_case_runs(options)

    json(conn, %{
      test_case_runs:
        Enum.map(runs, fn run ->
          %{
            id: run.id,
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

  defp fetch_stack_trace(nil), do: nil

  defp fetch_stack_trace(stack_trace_id) do
    case Tests.get_stack_trace_by_id(stack_trace_id) do
      {:ok, st} ->
        %{
          id: st.id,
          file_name: st.file_name,
          app_name: nullable_string(st.app_name),
          os_version: nullable_string(st.os_version),
          exception_type: nullable_string(st.exception_type),
          signal: nullable_string(st.signal),
          exception_subtype: nullable_string(st.exception_subtype),
          formatted_frames: nullable_string(st.formatted_frames)
        }

      {:error, :not_found} ->
        nil
    end
  end

  defp nullable_string(""), do: nil
  defp nullable_string(value), do: value

  defp format_ran_at(nil), do: nil

  defp format_ran_at(%NaiveDateTime{} = ran_at) do
    ran_at
    |> NaiveDateTime.truncate(:second)
    |> DateTime.from_naive!("Etc/UTC")
    |> DateTime.to_iso8601()
  end

  defp format_ran_at(%DateTime{} = ran_at), do: DateTime.to_iso8601(ran_at)

  defp build_run_filters(params) do
    filters = []

    filters =
      case Map.get(params, :test_case_id) do
        nil -> filters
        test_case_id -> [%{field: :test_case_id, op: :==, value: test_case_id} | filters]
      end

    filters =
      case Map.get(params, :test_run_id) do
        nil -> filters
        test_run_id -> [%{field: :test_run_id, op: :==, value: test_run_id} | filters]
      end

    filters =
      if Map.get(params, :flaky),
        do: [%{field: :is_flaky, op: :==, value: true} | filters],
        else: filters

    filters
  end
end
