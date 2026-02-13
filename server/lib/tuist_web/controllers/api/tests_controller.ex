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
