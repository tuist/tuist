defmodule TuistWeb.API.TestsController do
  use OpenApiSpex.ControllerSpecs
  use TuistWeb, :controller

  alias OpenApiSpex.Schema
  alias Tuist.Tests
  alias TuistWeb.API.Schemas.BuildSystem
  alias TuistWeb.API.Schemas.Error
  alias TuistWeb.API.Schemas.PaginationMetadata
  alias TuistWeb.API.Schemas.Tests.Test
  alias TuistWeb.Authentication

  plug(OpenApiSpex.Plug.CastAndValidate,
    json_render_error_v2: true,
    render_error: TuistWeb.RenderAPIErrorPlug
  )

  plug(TuistWeb.Plugs.LoaderPlug)
  plug(TuistWeb.API.Authorization.AuthorizationPlug, :test)

  tags ["Tests"]

  operation(:index,
    summary: "List test runs for a project.",
    operation_id: "listTestRuns",
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
      git_branch: [
        in: :query,
        type: :string,
        description: "Filter by git branch."
      ],
      status: [
        in: :query,
        type: %Schema{
          title: "TestRunStatus",
          type: :string,
          enum: ["success", "failure", "skipped"]
        },
        description: "Filter by test run status."
      ],
      scheme: [
        in: :query,
        type: :string,
        description: "Filter by scheme name."
      ],
      page: [
        in: :query,
        type: %Schema{
          title: "TestRunsIndexPage",
          description: "The page number to return.",
          type: :integer,
          default: 1,
          minimum: 1
        }
      ],
      page_size: [
        in: :query,
        type: %Schema{
          title: "TestRunsIndexPageSize",
          description: "The maximum number of test runs to return in a single page.",
          type: :integer,
          default: 20,
          minimum: 1,
          maximum: 100
        }
      ]
    ],
    responses: %{
      ok:
        {"List of test runs", "application/json",
         %Schema{
           type: :object,
           properties: %{
             test_runs: %Schema{
               type: :array,
               items: %Schema{
                 type: :object,
                 properties: %{
                   id: %Schema{type: :string, format: :uuid, description: "The test run ID."},
                   duration: %Schema{type: :integer, description: "Duration in milliseconds."},
                   status: %Schema{type: :string, enum: ["success", "failure", "skipped"], description: "Run status."},
                   is_ci: %Schema{type: :boolean, description: "Whether the run was on CI."},
                   is_flaky: %Schema{type: :boolean, description: "Whether the run was flaky."},
                   scheme: %Schema{type: :string, nullable: true, description: "Build scheme."},
                   git_branch: %Schema{type: :string, nullable: true, description: "Git branch."},
                   git_commit_sha: %Schema{type: :string, nullable: true, description: "Git commit SHA."},
                   ran_at: %Schema{
                     type: :string,
                     format: :"date-time",
                     nullable: true,
                     description: "ISO 8601 timestamp."
                   },
                   total_test_count: %Schema{type: :integer, description: "Total number of test cases."},
                   ran_tests: %Schema{type: :integer, description: "Number of test cases that ran."},
                   skipped_tests: %Schema{type: :integer, description: "Number of skipped test cases."}
                 },
                 required: [:id, :duration, :status, :is_ci, :is_flaky]
               }
             },
             pagination_metadata: PaginationMetadata
           },
           required: [:test_runs, :pagination_metadata]
         }},
      forbidden: {"You don't have permission to access this resource", "application/json", Error}
    }
  )

  def index(
        %{assigns: %{selected_project: selected_project}, params: %{page_size: page_size, page: page} = params} = conn,
        _params
      ) do
    filters = [%{field: :project_id, op: :==, value: selected_project.id}]

    filters =
      if Map.get(params, :git_branch) do
        filters ++ [%{field: :git_branch, op: :==, value: params.git_branch}]
      else
        filters
      end

    filters =
      if Map.get(params, :status) do
        filters ++ [%{field: :status, op: :==, value: params.status}]
      else
        filters
      end

    filters =
      if Map.get(params, :scheme) do
        filters ++ [%{field: :scheme, op: :==, value: params.scheme}]
      else
        filters
      end

    attrs = %{
      filters: filters,
      order_by: [:ran_at],
      order_directions: [:desc],
      page: page,
      page_size: page_size
    }

    {test_runs, meta} = Tests.list_test_runs(attrs)
    metrics_list = Tests.Analytics.test_runs_metrics(test_runs)
    metrics_map = Map.new(metrics_list, &{&1.test_run_id, &1})

    json(conn, %{
      test_runs:
        Enum.map(test_runs, fn run ->
          run_metrics = Map.get(metrics_map, run.id, %{})

          %{
            id: run.id,
            duration: run.duration,
            status: to_string(run.status),
            is_ci: run.is_ci,
            is_flaky: run.is_flaky,
            scheme: run.scheme,
            git_branch: run.git_branch,
            git_commit_sha: run.git_commit_sha,
            ran_at: format_ran_at(run.ran_at),
            total_test_count: Map.get(run_metrics, :total_tests, 0),
            ran_tests: Map.get(run_metrics, :ran_tests, 0),
            skipped_tests: Map.get(run_metrics, :skipped_tests, 0)
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

  operation(:create,
    summary: "Create a new test run.",
    parameters: [
      account_handle: [
        in: :path,
        type: :string,
        required: true,
        description: "The handle of the project's account."
      ],
      project_handle: [
        in: :path,
        type: :string,
        required: true,
        description: "The handle of the project to create a test run for."
      ]
    ],
    operation_id: "createTest",
    request_body:
      {"Test params", "application/json",
       %Schema{
         title: "TestParams",
         description: "Parameters to create a single test run.",
         type: :object,
         properties: %{
           duration: %Schema{
             description: "Duration of the run in milliseconds.",
             type: :integer
           },
           macos_version: %Schema{
             type: :string,
             description: "The version of macOS used during the run."
           },
           xcode_version: %Schema{
             type: :string,
             description: "The version of Xcode used during the run."
           },
           is_ci: %Schema{
             type: :boolean,
             description: "Indicates if the run was executed on a Continuous Integration (CI) system."
           },
           model_identifier: %Schema{
             type: :string,
             description: "Identifier for the model where the run was executed, such as MacBookAir10,1."
           },
           scheme: %Schema{
             type: :string,
             description: "The scheme used for the test run."
           },
           status: %Schema{
             type: :string,
             description: "The status of the test run.",
             enum: ["success", "failure", "skipped"]
           },
           git_commit_sha: %Schema{
             type: :string,
             description: "The commit SHA."
           },
           git_branch: %Schema{
             type: :string,
             description: "The git branch."
           },
           git_ref: %Schema{
             type: :string,
             description: "The git reference."
           },
           git_remote_url_origin: %Schema{
             type: :string,
             description: "The git remote URL origin."
           },
           build_run_id: %Schema{
             type: :string,
             description: "The UUID of an associated build run."
           },
           ci_run_id: %Schema{
             type: :string,
             description: "The CI run identifier (e.g., GitHub Actions run ID, GitLab pipeline ID)."
           },
           ci_project_handle: %Schema{
             type: :string,
             description: "The CI project handle (e.g., 'owner/repo' for GitHub, project path for GitLab)."
           },
           ci_host: %Schema{
             type: :string,
             description: "The CI host URL (optional, for self-hosted instances)."
           },
           ci_provider: %Schema{
             type: :string,
             description: "The CI provider.",
             enum: Tests.valid_ci_providers()
           },
           gradle_build_id: %Schema{
             type: :string,
             description: "The UUID of an associated Gradle build."
           },
           build_system: BuildSystem.schema(),
           test_modules: %Schema{
             type: :array,
             description: "The test modules associated with the test run.",
             items: %Schema{
               type: :object,
               properties: %{
                 name: %Schema{
                   type: :string,
                   description: "The name of the test module/target."
                 },
                 status: %Schema{
                   type: :string,
                   description: "The status of the test module.",
                   enum: ["success", "failure"]
                 },
                 duration: %Schema{
                   type: :integer,
                   description: "The duration of the test module in milliseconds."
                 },
                 test_suites: %Schema{
                   type: :array,
                   description: "The test suites within this module.",
                   items: %Schema{
                     type: :object,
                     properties: %{
                       name: %Schema{
                         type: :string,
                         description: "The name of the test suite."
                       },
                       status: %Schema{
                         type: :string,
                         description: "The status of the test suite.",
                         enum: ["success", "failure", "skipped"]
                       },
                       duration: %Schema{
                         type: :integer,
                         description: "The duration of the test suite in milliseconds."
                       }
                     },
                     required: [:name, :status, :duration]
                   }
                 },
                 test_cases: %Schema{
                   type: :array,
                   description: "The test cases within this module.",
                   items: %Schema{
                     type: :object,
                     properties: %{
                       name: %Schema{
                         type: :string,
                         description: "The name of the test case."
                       },
                       test_suite_name: %Schema{
                         type: :string,
                         description: "The name of the test suite this test case belongs to (optional)."
                       },
                       status: %Schema{
                         type: :string,
                         description: "The status of the test case.",
                         enum: ["success", "failure", "skipped"]
                       },
                       duration: %Schema{
                         type: :integer,
                         description: "The duration of the test case in milliseconds."
                       },
                       is_quarantined: %Schema{
                         type: :boolean,
                         description: "Whether this test case was quarantined when it ran."
                       },
                       failures: %Schema{
                         type: :array,
                         description: "The failures that occurred in this test case.",
                         items: %Schema{
                           type: :object,
                           properties: %{
                             message: %Schema{
                               type: :string,
                               description: "The failure message."
                             },
                             path: %Schema{
                               type: :string,
                               description: "The file path where the failure occurred, relative to the project root."
                             },
                             line_number: %Schema{
                               type: :integer,
                               description: "The line number where the failure occurred."
                             },
                             issue_type: %Schema{
                               type: :string,
                               description: "The type of issue that occurred.",
                               enum: ["error_thrown", "assertion_failure", "issue_recorded"]
                             }
                           },
                           required: [:line_number]
                         }
                       },
                       repetitions: %Schema{
                         type: :array,
                         description: "The repetition attempts for this test case (when run with retry-on-failure).",
                         items: %Schema{
                           type: :object,
                           properties: %{
                             repetition_number: %Schema{
                               type: :integer,
                               description: "The repetition attempt number (1 = First Run, 2 = Retry 1, etc.)"
                             },
                             name: %Schema{
                               type: :string,
                               description: "The name of the repetition (e.g., 'First Run', 'Retry 1')."
                             },
                             status: %Schema{
                               type: :string,
                               description: "The status of this repetition attempt.",
                               enum: ["success", "failure"]
                             },
                             duration: %Schema{
                               type: :integer,
                               description: "The duration of this repetition in milliseconds."
                             }
                           },
                           required: [:repetition_number, :name, :status]
                         }
                       }
                     },
                     required: [:name, :status, :duration]
                   }
                 }
               },
               required: [:name, :status, :duration]
             }
           }
         },
         required: [
           :duration,
           :test_modules,
           :is_ci
         ]
       }},
    responses: %{
      ok: {
        "The created test run",
        "application/json",
        Test
      },
      unauthorized: {"You need to be authenticated to create a test run", "application/json", Error},
      forbidden: {"The authenticated subject is not authorized to perform this action", "application/json", Error},
      not_found: {"The project doesn't exist", "application/json", Error},
      bad_request: {"The request parameters are invalid", "application/json", Error}
    }
  )

  def create(%{assigns: %{selected_project: selected_project}, body_params: body_params} = conn, _params) do
    run_params =
      body_params
      |> Map.put(:project, selected_project)
      |> Map.put(:account, Authentication.authenticated_subject_account(conn))

    case get_or_create_test(run_params) do
      {:ok, test_run} ->
        Tuist.VCS.enqueue_vcs_pull_request_comment(%{
          git_commit_sha: Map.get(body_params, :git_commit_sha),
          git_ref: Map.get(body_params, :git_ref),
          git_remote_url_origin: Map.get(body_params, :git_remote_url_origin),
          project_id: selected_project.id,
          preview_url_template: "#{url(~p"/")}:account_name/:project_name/previews/:preview_id",
          preview_qr_code_url_template: "#{url(~p"/")}:account_name/:project_name/previews/:preview_id/qr-code.png",
          command_run_url_template: "#{url(~p"/")}:account_name/:project_name/runs/:command_event_id",
          test_run_url_template: "#{url(~p"/")}:account_name/:project_name/tests/test-runs/:test_run_id",
          bundle_url_template: "#{url(~p"/")}:account_name/:project_name/bundles/:bundle_id",
          build_url_template: "#{url(~p"/")}:account_name/:project_name/builds/build-runs/:build_id"
        })

        conn
        |> put_status(:ok)
        |> json(%{
          type: "test",
          id: test_run.id,
          duration: test_run.duration,
          project_id: test_run.project_id,
          url: url(~p"/#{selected_project.account.name}/#{selected_project.name}/tests/test-runs/#{test_run.id}"),
          test_case_runs:
            Enum.map(test_run.test_case_runs, fn run ->
              %{
                id: run.id,
                name: run.name,
                module_name: run.module_name,
                suite_name: run.suite_name
              }
            end)
        })

      {:error, _changeset} ->
        conn |> put_status(:bad_request) |> json(%{message: "The request parameters are invalid"})
    end
  end

  operation(:show,
    summary: "Get a test run by ID.",
    operation_id: "getTestRun",
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
      ]
    ],
    responses: %{
      ok:
        {"Test run details", "application/json",
         %Schema{
           type: :object,
           properties: %{
             id: %Schema{type: :string, format: :uuid, description: "The test run ID."},
             status: %Schema{type: :string, enum: ["success", "failure", "skipped"], description: "Run status."},
             duration: %Schema{type: :integer, description: "Duration in milliseconds."},
             is_ci: %Schema{type: :boolean, description: "Whether the run was on CI."},
             is_flaky: %Schema{type: :boolean, description: "Whether the run was flaky."},
             scheme: %Schema{type: :string, nullable: true, description: "Build scheme."},
             macos_version: %Schema{type: :string, nullable: true, description: "macOS version."},
             xcode_version: %Schema{type: :string, nullable: true, description: "Xcode version."},
             model_identifier: %Schema{type: :string, nullable: true, description: "Model identifier."},
             device_name: %Schema{type: :string, nullable: true, description: "Human-readable device name."},
             git_branch: %Schema{type: :string, nullable: true, description: "Git branch."},
             git_commit_sha: %Schema{type: :string, nullable: true, description: "Git commit SHA."},
             ran_at: %Schema{
               type: :string,
               format: :"date-time",
               nullable: true,
               description: "ISO 8601 timestamp when the run executed."
             },
             total_test_count: %Schema{type: :integer, description: "Total number of test cases."},
             failed_test_count: %Schema{type: :integer, description: "Number of failed test cases."},
             flaky_test_count: %Schema{type: :integer, description: "Number of flaky test cases."},
             avg_test_duration: %Schema{type: :integer, description: "Average test case duration in milliseconds."}
           },
           required: [
             :id,
             :status,
             :duration,
             :is_ci,
             :is_flaky,
             :total_test_count,
             :failed_test_count,
             :flaky_test_count,
             :avg_test_duration
           ]
         }},
      not_found: {"Test run not found", "application/json", Error},
      forbidden: {"You don't have permission to access this resource", "application/json", Error}
    }
  )

  def show(%{assigns: %{selected_project: selected_project}, params: %{test_run_id: test_run_id}} = conn, _params) do
    case Tests.get_test(test_run_id) do
      {:ok, %{project_id: project_id} = run} when project_id == selected_project.id ->
        test_metrics = Tests.Analytics.get_test_run_metrics(run.id)

        json(conn, %{
          id: run.id,
          status: to_string(run.status),
          duration: run.duration,
          is_ci: run.is_ci,
          is_flaky: run.is_flaky,
          scheme: run.scheme,
          macos_version: run.macos_version,
          xcode_version: run.xcode_version,
          model_identifier: run.model_identifier,
          git_branch: run.git_branch,
          git_commit_sha: run.git_commit_sha,
          ran_at: format_ran_at(run.ran_at),
          total_test_count: test_metrics.total_count,
          failed_test_count: test_metrics.failed_count,
          flaky_test_count: test_metrics.flaky_count,
          avg_test_duration: test_metrics.avg_duration
        })

      _error ->
        conn
        |> put_status(:not_found)
        |> json(%{message: "Test run not found."})
    end
  end

  defp format_ran_at(nil), do: nil

  defp format_ran_at(%NaiveDateTime{} = ran_at) do
    ran_at |> NaiveDateTime.truncate(:second) |> DateTime.from_naive!("Etc/UTC") |> DateTime.to_iso8601()
  end

  defp format_ran_at(%DateTime{} = ran_at), do: DateTime.to_iso8601(ran_at)

  defp get_or_create_test(params) do
    test_id = Map.get(params, :id, UUIDv7.generate())

    case Tests.get_test(test_id) do
      {:ok, test_run} ->
        {:ok, test_run}

      {:error, :not_found} ->
        Tests.create_test(%{
          id: test_id,
          duration: params.duration,
          macos_version: Map.get(params, :macos_version),
          xcode_version: Map.get(params, :xcode_version),
          is_ci: Map.get(params, :is_ci),
          model_identifier: Map.get(params, :model_identifier),
          scheme: Map.get(params, :scheme),
          project_id: params.project.id,
          account_id: params.account.id,
          status: Map.get(params, :status),
          git_branch: Map.get(params, :git_branch),
          git_commit_sha: Map.get(params, :git_commit_sha),
          git_ref: Map.get(params, :git_ref),
          ran_at: Map.get(params, :ran_at, NaiveDateTime.utc_now()),
          ci_run_id: Map.get(params, :ci_run_id),
          ci_project_handle: Map.get(params, :ci_project_handle),
          ci_host: Map.get(params, :ci_host),
          ci_provider: Map.get(params, :ci_provider),
          build_system: Map.get(params, :build_system, "xcode"),
          test_modules: Map.get(params, :test_modules, []),
          test_cases: Map.get(params, :test_cases, []),
          build_run_id: Map.get(params, :build_run_id),
          gradle_build_id: Map.get(params, :gradle_build_id)
        })
    end
  end
end
