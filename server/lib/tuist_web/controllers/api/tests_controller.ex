defmodule TuistWeb.API.TestsController do
  use OpenApiSpex.ControllerSpecs
  use TuistWeb, :controller

  alias OpenApiSpex.Schema
  alias Tuist.Tests
  alias TuistWeb.API.Schemas.Error
  alias TuistWeb.API.Schemas.Tests.Test
  alias TuistWeb.Authentication

  plug(OpenApiSpex.Plug.CastAndValidate,
    json_render_error_v2: true,
    render_error: TuistWeb.RenderAPIErrorPlug
  )

  plug(TuistWeb.Plugs.LoaderPlug)
  plug(TuistWeb.API.Authorization.AuthorizationPlug, :test)

  tags ["Tests"]

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
                       stack_trace_id: %Schema{
                         type: :string,
                         description: "The deterministic UUID of the crash stack trace associated with this test case."
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
           :macos_version,
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
        conn
        |> put_status(:ok)
        |> json(%{
          type: "test",
          id: test_run.id,
          duration: test_run.duration,
          project_id: test_run.project_id,
          url: url(~p"/#{selected_project.account.name}/#{selected_project.name}/tests/test-runs/#{test_run.id}")
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
           required: [:id, :status, :duration, :is_ci, :is_flaky, :total_test_count, :failed_test_count, :flaky_test_count, :avg_test_duration]
         }},
      not_found: {"Test run not found", "application/json", Error},
      forbidden: {"You don't have permission to access this resource", "application/json", Error}
    }
  )

  def show(
        %{assigns: %{selected_project: selected_project}, params: %{test_run_id: test_run_id}} = conn,
        _params
      ) do
    case Tests.get_test(test_run_id) do
      {:ok, run} ->
        if run.project_id == selected_project.id do
          test_metrics = Tests.Analytics.get_test_run_metrics(run.id)

          json(conn, %{
            id: run.id,
            status: to_string(run.status),
            duration: run.duration,
            is_ci: run.is_ci,
            is_flaky: run.is_flaky,
            scheme: nullable_string(run.scheme),
            macos_version: nullable_string(run.macos_version),
            xcode_version: nullable_string(run.xcode_version),
            model_identifier: nullable_string(run.model_identifier),
            device_name: resolve_device_name(run.model_identifier),
            git_branch: nullable_string(run.git_branch),
            git_commit_sha: nullable_string(run.git_commit_sha),
            ran_at: format_ran_at(run.ran_at),
            total_test_count: test_metrics.total_count,
            failed_test_count: test_metrics.failed_count,
            flaky_test_count: test_metrics.flaky_count,
            avg_test_duration: test_metrics.avg_duration
          })
        else
          conn
          |> put_status(:not_found)
          |> json(%{message: "Test run not found."})
        end

      {:error, :not_found} ->
        conn
        |> put_status(:not_found)
        |> json(%{message: "Test run not found."})
    end
  end

  defp nullable_string(""), do: nil
  defp nullable_string(value), do: value

  defp resolve_device_name(nil), do: nil
  defp resolve_device_name(""), do: nil

  defp resolve_device_name(model_identifier) do
    Tuist.Apple.devices()[model_identifier] || model_identifier
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
          test_modules: Map.get(params, :test_modules, []),
          test_cases: Map.get(params, :test_cases, []),
          build_run_id: Map.get(params, :build_run_id)
        })
    end
  end
end
