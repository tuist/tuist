defmodule TuistWeb.API.RunsController do
  use OpenApiSpex.ControllerSpecs
  use TuistWeb, :controller

  alias OpenApiSpex.Schema
  alias Tuist.Runs
  alias Tuist.Runs.CASOutput
  alias TuistWeb.API.Schemas.Error
  alias TuistWeb.API.Schemas.Run
  alias TuistWeb.API.Schemas.Runs.Build
  alias TuistWeb.API.Schemas.Runs.Test
  alias TuistWeb.Authentication

  plug(OpenApiSpex.Plug.CastAndValidate,
    json_render_error_v2: true,
    render_error: TuistWeb.RenderAPIErrorPlug
  )

  plug(TuistWeb.Plugs.LoaderPlug)
  plug(TuistWeb.API.Authorization.AuthorizationPlug, :run)

  tags ["Runs"]

  operation(:index,
    summary: "List runs associated with a given project.",
    operation_id: "listRuns",
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
        description: "The name of the run."
      ],
      git_ref: [
        in: :query,
        type: :string,
        description: "The git ref of the run."
      ],
      git_branch: [
        in: :query,
        type: :string,
        description: "The git branch of the run."
      ],
      git_commit_sha: [
        in: :query,
        type: :string,
        description: "The git commit SHA of the run."
      ],
      page_size: [
        in: :query,
        type: %Schema{
          title: "RunsIndexPageSize",
          description: "The maximum number of runs to return in a single page.",
          type: :integer,
          default: 20,
          minimum: 1,
          maximum: 100
        }
      ],
      page: [
        in: :query,
        type: %Schema{
          title: "RunsIndexPage",
          description: "The page number to return.",
          type: :integer,
          default: 1,
          minimum: 1
        }
      ]
    ],
    responses: %{
      ok:
        {"List of runs", "application/json",
         %Schema{
           type: :object,
           properties: %{
             runs: %Schema{
               type: :array,
               items: Run
             }
           },
           required: [:runs]
         }},
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

    {command_events, _meta} =
      Tuist.CommandEvents.list_command_events(%{
        page: page,
        page_size: page_size,
        filters: filters,
        order_by: [:ran_at],
        order_directions: [:desc]
      })

    json(conn, %{
      runs:
        Enum.map(command_events, fn event ->
          ran_by =
            case Tuist.CommandEvents.get_user_for_command_event(event) do
              {:ok, user} ->
                user = Tuist.Repo.preload(user, :account)
                %{handle: user.account.name}

              {:error, :not_found} ->
                nil
            end

          event
          |> Map.take([
            :legacy_id,
            :id,
            :name,
            :duration,
            :subcommand,
            :command_arguments,
            :tuist_version,
            :swift_version,
            :macos_version,
            :status,
            :git_ref,
            :git_commit_sha,
            :git_branch,
            :cacheable_targets,
            :local_cache_target_hits,
            :remote_cache_target_hits,
            :test_targets,
            :local_test_target_hits,
            :remote_test_target_hits,
            :preview_id
          ])
          |> Map.put(:id, event.legacy_id)
          |> Map.put(:uuid, event.id)
          |> Map.delete(:legacy_id)
          |> Map.put(
            :url,
            ~p"/#{selected_project.account.name}/#{selected_project.name}/runs/#{event.id}"
          )
          |> Map.put(
            :ran_at,
            event.created_at |> DateTime.from_naive!("Etc/UTC") |> DateTime.to_unix()
          )
          |> Map.put(:ran_by, ran_by)
        end)
    })
  end

  operation(:create,
    summary: "Create a new run.",
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
        description: "The handle of the project to create a build for."
      ]
    ],
    operation_id: "createRun",
    request_body:
      {"Run params", "application/json",
       %Schema{
         title: "RunParams",
         description: "Parameters to create a single run.",
         oneOf: [
           %Schema{
             title: "BuildRun",
             type: :object,
             properties: %{
               type: %Schema{
                 type: :string,
                 enum: ["build"],
                 description: "The type of the run, which is 'build' in this case."
               },
               id: %Schema{
                 description: "UUID of a run generated by the system.",
                 type: :string
               },
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
                 description: "The scheme used for the build."
               },
               configuration: %Schema{
                 type: :string,
                 description: "The build configuration (e.g., Debug, Release)."
               },
               status: %Schema{
                 type: :string,
                 description: "The status of the build run.",
                 enum: [:success, :failure]
               },
               category: %Schema{
                 type: :string,
                 description: "The category of the build run, can be clean or incremental.",
                 enum: [:clean, :incremental]
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
                 enum: [:github, :gitlab, :bitrise, :circleci, :buildkite, :codemagic]
               },
               issues: %Schema{
                 type: :array,
                 description: "The build issues associated with the build run.",
                 items: %Schema{
                   type: :object,
                   properties: %{
                     type: %Schema{
                       type: :string,
                       description: "The type of the issue.",
                       enum: [:warning, :error]
                     },
                     target: %Schema{
                       type: :string,
                       description: "The target name associated with the issue."
                     },
                     project: %Schema{
                       type: :string,
                       description: "The project name associated with the issue."
                     },
                     title: %Schema{
                       type: :string,
                       description: "The title of the build issue."
                     },
                     signature: %Schema{
                       type: :string,
                       description: "The signature of the issue."
                     },
                     step_type: %Schema{
                       type: :string,
                       description: "The step type where the issue occurred, such as swift_compilation.",
                       enum: [
                         :c_compilation,
                         :swift_compilation,
                         :script_execution,
                         :create_static_library,
                         :linker,
                         :copy_swift_libs,
                         :compile_assets_catalog,
                         :compile_storyboard,
                         :write_auxiliary_file,
                         :link_storyboards,
                         :copy_resource_file,
                         :merge_swift_module,
                         :xib_compilation,
                         :swift_aggregated_compilation,
                         :precompile_bridging_header,
                         :other,
                         :validate_embedded_binary,
                         :validate
                       ]
                     },
                     path: %Schema{
                       type: :string,
                       description: "The file path where the issue occurred, relative to the project root."
                     },
                     message: %Schema{
                       type: :string,
                       description: "The detailed message of the issue."
                     },
                     starting_line: %Schema{
                       type: :integer,
                       description: "The starting line number of the issue."
                     },
                     ending_line: %Schema{
                       type: :integer,
                       description: "The ending line number of the issue."
                     },
                     starting_column: %Schema{
                       type: :integer,
                       description: "The starting column number of the issue."
                     },
                     ending_column: %Schema{
                       type: :integer,
                       description: "The ending column number of the issue."
                     }
                   },
                   required: [
                     :type,
                     :target,
                     :project,
                     :title,
                     :signature,
                     :step_type,
                     :starting_line,
                     :ending_line,
                     :starting_column,
                     :ending_column
                   ]
                 }
               },
               files: %Schema{
                 type: :array,
                 description: "Compiled files associated with the build run.",
                 items: %Schema{
                   type: :object,
                   properties: %{
                     type: %Schema{
                       type: :string,
                       description: "The type of the file.",
                       enum: [:swift, :c]
                     },
                     target: %Schema{
                       type: :string,
                       description: "The target name associated with the file."
                     },
                     project: %Schema{
                       type: :string,
                       description: "The project name associated with the file."
                     },
                     path: %Schema{
                       type: :string,
                       description: "The file path where the issue occurred, relative to the project root."
                     },
                     compilation_duration: %Schema{
                       type: :integer,
                       description: "The duration of the compilation for the file in milliseconds."
                     }
                   },
                   required: [
                     :type,
                     :target,
                     :project,
                     :path,
                     :compilation_duration
                   ]
                 }
               },
               targets: %Schema{
                 type: :array,
                 description: "Targets with build metadata associated with the build run.",
                 items: %Schema{
                   type: :object,
                   properties: %{
                     name: %Schema{
                       type: :string,
                       description: "The target name."
                     },
                     project: %Schema{
                       type: :string,
                       description: "The target's project name."
                     },
                     build_duration: %Schema{
                       type: :integer,
                       description: "The build duration for the target in milliseconds."
                     },
                     compilation_duration: %Schema{
                       type: :integer,
                       description: "The duration of the compilation for the target in milliseconds."
                     },
                     status: %Schema{
                       type: :string,
                       description: "The status of the target's build.",
                       enum: [:success, :failure]
                     }
                   },
                   required: [
                     :name,
                     :project,
                     :build_duration,
                     :compilation_duration,
                     :status
                   ]
                 }
               },
               cacheable_tasks: %Schema{
                 type: :array,
                 description: "Cacheable tasks associated with the build run.",
                 items: %Schema{
                   type: :object,
                   properties: %{
                     type: %Schema{
                       type: :string,
                       description: "The type of cacheable task.",
                       enum: [:clang, :swift]
                     },
                     status: %Schema{
                       type: :string,
                       description: "The cache status of the task.",
                       enum: [:hit_local, :hit_remote, :miss]
                     },
                     key: %Schema{
                       type: :string,
                       description: "The cache key of the task."
                     },
                     read_duration: %Schema{
                       type: :number,
                       description: "The duration in milliseconds for reading from cache."
                     },
                     write_duration: %Schema{
                       type: :number,
                       description: "The duration in milliseconds for writing to cache."
                     },
                     description: %Schema{
                       type: :string,
                       description: "Optional description of the cacheable task."
                     },
                     cas_output_node_ids: %Schema{
                       type: :array,
                       description: "Array of CAS output node IDs associated with this cacheable task.",
                       items: %Schema{type: :string}
                     }
                   },
                   required: [:type, :status, :key]
                 }
               },
               cas_outputs: %Schema{
                 type: :array,
                 description: "CAS output operations associated with the build run.",
                 items: %Schema{
                   type: :object,
                   properties: %{
                     node_id: %Schema{
                       type: :string,
                       description: "The CAS node identifier."
                     },
                     checksum: %Schema{
                       type: :string,
                       description: "The checksum of the CAS object."
                     },
                     size: %Schema{
                       type: :integer,
                       description: "The size of the CAS object in bytes."
                     },
                     duration: %Schema{
                       type: :number,
                       description: "The duration of the CAS operation in milliseconds."
                     },
                     compressed_size: %Schema{
                       type: :integer,
                       description: "The compressed size of the CAS object in bytes."
                     },
                     operation: %Schema{
                       type: :string,
                       description: "The type of CAS operation.",
                       enum: [:download, :upload]
                     },
                     type: %Schema{
                       type: :string,
                       description: "The type of the CAS output file.",
                       enum: Enum.map(CASOutput.valid_types(), &String.to_atom/1)
                     }
                   },
                   required: [:node_id, :checksum, :size, :duration, :compressed_size, :operation]
                 }
               }
             },
             required: [
               :id,
               :duration,
               :is_ci
             ]
           },
           %Schema{
             title: "TestRun",
             type: :object,
             properties: %{
               type: %Schema{
                 type: :string,
                 enum: ["test"],
                 description: "The type of the run, which is 'test' in this case."
               },
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
                 enum: Runs.valid_ci_providers()
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
               :type,
               :duration,
               :test_modules,
               :macos_version,
               :is_ci
             ]
           }
         ]
       }},
    responses: %{
      ok: {
        "The created run",
        "application/json",
        %Schema{
          oneOf: [Build, Test]
        }
      },
      unauthorized: {"You need to be authenticated to create a run", "application/json", Error},
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

    case Map.get(body_params, :type, "build") do
      "build" ->
        case get_or_create_build(run_params) do
          {:ok, build} ->
            Tuist.VCS.enqueue_vcs_pull_request_comment(%{
              build_id: build.id,
              git_commit_sha: build.git_commit_sha,
              git_ref: build.git_ref,
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
              type: "build",
              id: build.id,
              duration: build.duration,
              project_id: build.project_id,
              url: url(~p"/#{selected_project.account.name}/#{selected_project.name}/builds/build-runs/#{build.id}")
            })

          {:error, _changeset} ->
            conn |> put_status(:bad_request) |> json(%{message: "The request parameters are invalid"})
        end

      "test" ->
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

      _ ->
        conn |> put_status(:bad_request) |> json(%{message: "Invalid run type"})
    end
  end

  defp get_or_create_build(params) do
    case Runs.get_build(params.id) do
      %Runs.Build{} = build ->
        {:ok, build}

      nil ->
        build_attrs = %{
          id: params.id,
          duration: params.duration,
          macos_version: Map.get(params, :macos_version),
          xcode_version: Map.get(params, :xcode_version),
          is_ci: Map.get(params, :is_ci),
          model_identifier: Map.get(params, :model_identifier),
          scheme: Map.get(params, :scheme),
          configuration: Map.get(params, :configuration),
          project_id: params.project.id,
          account_id: params.account.id,
          status: Map.get(params, :status, :success),
          category: Map.get(params, :category),
          git_branch: Map.get(params, :git_branch),
          git_commit_sha: Map.get(params, :git_commit_sha),
          git_ref: Map.get(params, :git_ref),
          ci_run_id: Map.get(params, :ci_run_id),
          ci_project_handle: Map.get(params, :ci_project_handle),
          ci_host: Map.get(params, :ci_host),
          ci_provider: Map.get(params, :ci_provider),
          issues: Map.get(params, :issues, []),
          files: Map.get(params, :files, []),
          targets: Map.get(params, :targets, []),
          cacheable_tasks: Map.get(params, :cacheable_tasks, []),
          cas_outputs: Map.get(params, :cas_outputs, [])
        }

        build_attrs
        |> Runs.create_build()
        |> handle_build_creation_result(params.id)
    end
  end

  defp handle_build_creation_result({:ok, build}, _build_id), do: {:ok, build}

  defp handle_build_creation_result({:error, changeset}, build_id) do
    if Keyword.has_key?(changeset.errors, :id) do
      case Runs.get_build(build_id) do
        %Runs.Build{} = build -> {:ok, build}
        nil -> {:error, :creation_failed}
      end
    else
      {:error, changeset}
    end
  end

  defp get_or_create_test(params) do
    test_id = Map.get(params, :id, UUIDv7.generate())

    case Runs.get_test(test_id) do
      {:ok, test_run} ->
        {:ok, test_run}

      {:error, :not_found} ->
        Runs.create_test(%{
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

  defp filters_from_params(params) do
    [:name, :git_ref, :git_branch, :git_commit_sha]
    |> Enum.map(&%{field: &1, op: :==, value: Map.get(params, &1)})
    |> Enum.filter(&(&1.value != nil))
  end
end
