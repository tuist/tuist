defmodule TuistWeb.API.GradleController do
  use OpenApiSpex.ControllerSpecs
  use TuistWeb, :controller

  alias OpenApiSpex.Schema
  alias Tuist.Gradle
  alias TuistWeb.API.Schemas.Error
  alias TuistWeb.API.Schemas.PaginationMetadata

  plug(TuistWeb.Plugs.InstrumentedCastAndValidate,
    json_render_error_v2: true,
    render_error: TuistWeb.RenderAPIErrorPlug
  )

  plug(TuistWeb.Plugs.LoaderPlug)
  plug(TuistWeb.API.Authorization.AuthorizationPlug, :build)

  tags ["Gradle"]

  operation(:create_build,
    summary: "Create a Gradle build with task data.",
    operation_id: "createGradleBuild",
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
      ]
    ],
    request_body:
      {"Gradle build data", "application/json",
       %Schema{
         type: :object,
         properties: %{
           id: %Schema{type: :string, nullable: true, description: "Client-provided build ID (UUID)."},
           duration_ms: %Schema{type: :integer, description: "Build duration in milliseconds."},
           status: %Schema{type: :string, enum: ["success", "failure", "cancelled"], description: "Build status."},
           gradle_version: %Schema{type: :string, nullable: true, description: "Gradle version."},
           java_version: %Schema{type: :string, nullable: true, description: "Java version."},
           is_ci: %Schema{type: :boolean, description: "Whether the build ran on CI."},
           git_branch: %Schema{type: :string, nullable: true, description: "Git branch."},
           git_commit_sha: %Schema{type: :string, nullable: true, description: "Git commit SHA."},
           git_ref: %Schema{type: :string, nullable: true, description: "Git ref."},
           git_remote_url_origin: %Schema{
             type: :string,
             nullable: true,
             description: "Git remote URL origin."
           },
           root_project_name: %Schema{
             type: :string,
             nullable: true,
             description: "Root project name."
           },
           requested_tasks: %Schema{
             type: :array,
             items: %Schema{type: :string},
             nullable: true,
             description: "The tasks requested by the user (e.g., assembleRelease)."
           },
           tasks: %Schema{
             type: :array,
             items: %Schema{
               type: :object,
               properties: %{
                 task_path: %Schema{type: :string, description: "Task path (e.g., :app:compileKotlin)."},
                 task_type: %Schema{type: :string, nullable: true, description: "Task type class name."},
                 outcome: %Schema{
                   type: :string,
                   enum: ["local_hit", "remote_hit", "up_to_date", "executed", "failed", "skipped", "no_source"],
                   description: "Task outcome."
                 },
                 cacheable: %Schema{type: :boolean, description: "Whether the task is cacheable."},
                 duration_ms: %Schema{type: :integer, nullable: true, description: "Task duration in milliseconds."},
                 cache_key: %Schema{type: :string, nullable: true, description: "Cache key for cacheable tasks."},
                 cache_artifact_size: %Schema{
                   type: :integer,
                   nullable: true,
                   description: "Size of cache artifact in bytes."
                 },
                 started_at: %Schema{
                   type: :string,
                   format: :"date-time",
                   nullable: true,
                   description: "When the task started executing."
                 }
               },
               required: [:task_path, :outcome]
             }
           },
           machine_metrics: %Schema{
             type: :array,
             description: "Machine performance metrics collected during the build.",
             items: %Schema{
               type: :object,
               properties: %{
                 timestamp: %Schema{type: :number, description: "Unix timestamp in seconds."},
                 cpu_usage_percent: %Schema{type: :number, description: "CPU usage percentage (0-100)."},
                 memory_used_bytes: %Schema{type: :integer, description: "Memory used in bytes."},
                 memory_total_bytes: %Schema{type: :integer, description: "Total memory in bytes."},
                 network_bytes_in: %Schema{type: :integer, description: "Network bytes received per second."},
                 network_bytes_out: %Schema{type: :integer, description: "Network bytes sent per second."},
                 disk_bytes_read: %Schema{type: :integer, description: "Disk bytes read per second."},
                 disk_bytes_written: %Schema{type: :integer, description: "Disk bytes written per second."}
               },
               required: [
                 :timestamp,
                 :cpu_usage_percent,
                 :memory_used_bytes,
                 :memory_total_bytes,
                 :network_bytes_in,
                 :network_bytes_out,
                 :disk_bytes_read,
                 :disk_bytes_written
               ]
             }
           }
         },
         required: [:duration_ms, :status, :tasks]
       }},
    responses: %{
      created:
        {"Build created", "application/json",
         %Schema{
           type: :object,
           properties: %{
             id: %Schema{type: :string, format: :uuid, description: "The build ID."}
           },
           required: [:id]
         }},
      bad_request: {"Invalid request", "application/json", Error},
      forbidden: {"You don't have permission to access this resource", "application/json", Error}
    }
  )

  def create_build(%{assigns: %{selected_project: project}, body_params: body} = conn, _params) do
    tasks =
      Enum.map(body.tasks, fn task ->
        %{
          task_path: task.task_path,
          task_type: task[:task_type],
          outcome: task.outcome,
          cacheable: task[:cacheable] || false,
          duration_ms: task[:duration_ms] || 0,
          cache_key: task[:cache_key],
          cache_artifact_size: task[:cache_artifact_size],
          started_at: task[:started_at]
        }
      end)

    attrs = %{
      id: body[:id] || UUIDv7.generate(),
      project_id: project.id,
      account_id: TuistWeb.Authentication.authenticated_subject_account(conn).id,
      duration_ms: body.duration_ms,
      status: body.status,
      gradle_version: body[:gradle_version],
      java_version: body[:java_version],
      is_ci: body[:is_ci] || false,
      git_branch: body[:git_branch],
      git_commit_sha: body[:git_commit_sha],
      git_ref: body[:git_ref],
      root_project_name: body[:root_project_name],
      requested_tasks: body[:requested_tasks] || [],
      tasks: tasks,
      machine_metrics: Map.get(body, :machine_metrics, [])
    }

    {:ok, build_id} = Gradle.create_build(attrs)

    Tuist.VCS.enqueue_vcs_pull_request_comment(%{
      git_commit_sha: body[:git_commit_sha],
      git_ref: body[:git_ref],
      git_remote_url_origin: body[:git_remote_url_origin],
      project_id: project.id,
      preview_url_template: "#{url(~p"/")}:account_name/:project_name/previews/:preview_id",
      preview_qr_code_url_template: "#{url(~p"/")}:account_name/:project_name/previews/:preview_id/qr-code.png",
      command_run_url_template: "#{url(~p"/")}:account_name/:project_name/runs/:command_event_id",
      test_run_url_template: "#{url(~p"/")}:account_name/:project_name/tests/test-runs/:test_run_id",
      bundle_url_template: "#{url(~p"/")}:account_name/:project_name/bundles/:bundle_id",
      build_url_template: "#{url(~p"/")}:account_name/:project_name/builds/build-runs/:build_id"
    })

    conn
    |> put_status(:created)
    |> json(%{id: build_id})
  end

  operation(:list_builds,
    summary: "List Gradle builds for a project.",
    operation_id: "listGradleBuilds",
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
          title: "GradleBuildStatus",
          type: :string,
          enum: ["success", "failure", "cancelled"]
        },
        description: "Filter by build status."
      ],
      page_size: [
        in: :query,
        type: %Schema{
          title: "GradleBuildsIndexPageSize",
          description: "The maximum number of builds to return in a single page.",
          type: :integer,
          default: 20,
          minimum: 1,
          maximum: 100
        }
      ],
      page: [
        in: :query,
        type: %Schema{
          title: "GradleBuildsIndexPage",
          description: "The page number to return.",
          type: :integer,
          default: 1,
          minimum: 1
        }
      ]
    ],
    responses: %{
      ok:
        {"List of Gradle builds", "application/json",
         %Schema{
           type: :object,
           properties: %{
             builds: %Schema{
               type: :array,
               items: %Schema{
                 type: :object,
                 properties: %{
                   id: %Schema{type: :string, format: :uuid},
                   duration_ms: %Schema{type: :integer},
                   status: %Schema{type: :string, enum: ["success", "failure", "cancelled"]},
                   gradle_version: %Schema{type: :string, nullable: true},
                   java_version: %Schema{type: :string, nullable: true},
                   is_ci: %Schema{type: :boolean},
                   git_branch: %Schema{type: :string, nullable: true},
                   git_commit_sha: %Schema{type: :string, nullable: true},
                   root_project_name: %Schema{type: :string, nullable: true},
                   requested_tasks: %Schema{type: :array, items: %Schema{type: :string}},
                   tasks_local_hit_count: %Schema{type: :integer},
                   tasks_remote_hit_count: %Schema{type: :integer},
                   tasks_up_to_date_count: %Schema{type: :integer},
                   tasks_executed_count: %Schema{type: :integer},
                   cacheable_tasks_count: %Schema{type: :integer},
                   cache_hit_rate: %Schema{type: :number, nullable: true},
                   inserted_at: %Schema{type: :string, format: :"date-time"}
                 }
               }
             },
             pagination_metadata: PaginationMetadata
           },
           required: [:builds, :pagination_metadata]
         }},
      forbidden: {"You don't have permission to access this resource", "application/json", Error}
    }
  )

  def list_builds(
        %{assigns: %{selected_project: project}, params: %{page_size: page_size, page: page} = params} = conn,
        _params
      ) do
    filters = [%{field: :project_id, op: :==, value: project.id}]

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

    {builds, meta} =
      Gradle.list_builds(project.id, %{
        filters: filters,
        order_by: [:inserted_at],
        order_directions: [:desc],
        page: page,
        page_size: page_size
      })

    json(conn, %{
      builds:
        Enum.map(builds, fn build ->
          %{
            id: build.id,
            duration_ms: build.duration_ms,
            status: build.status,
            gradle_version: build.gradle_version,
            java_version: build.java_version,
            is_ci: build.is_ci,
            git_branch: build.git_branch,
            git_commit_sha: build.git_commit_sha,
            root_project_name: build.root_project_name,
            requested_tasks: build.requested_tasks,
            tasks_local_hit_count: build.tasks_local_hit_count,
            tasks_remote_hit_count: build.tasks_remote_hit_count,
            tasks_up_to_date_count: build.tasks_up_to_date_count,
            tasks_executed_count: build.tasks_executed_count,
            cacheable_tasks_count: build.cacheable_tasks_count,
            cache_hit_rate: Gradle.cache_hit_rate(build),
            inserted_at: build.inserted_at
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

  operation(:get_build,
    summary: "Get a Gradle build by ID.",
    operation_id: "getGradleBuild",
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
      build_id: [
        in: :path,
        type: :string,
        required: true,
        description: "The build ID."
      ]
    ],
    responses: %{
      ok:
        {"Gradle build details", "application/json",
         %Schema{
           type: :object,
           properties: %{
             id: %Schema{type: :string, format: :uuid},
             duration_ms: %Schema{type: :integer},
             status: %Schema{type: :string, enum: ["success", "failure", "cancelled"]},
             gradle_version: %Schema{type: :string, nullable: true},
             java_version: %Schema{type: :string, nullable: true},
             is_ci: %Schema{type: :boolean},
             git_branch: %Schema{type: :string, nullable: true},
             git_commit_sha: %Schema{type: :string, nullable: true},
             git_ref: %Schema{type: :string, nullable: true},
             root_project_name: %Schema{type: :string, nullable: true},
             requested_tasks: %Schema{type: :array, items: %Schema{type: :string}},
             tasks_local_hit_count: %Schema{type: :integer},
             tasks_remote_hit_count: %Schema{type: :integer},
             tasks_up_to_date_count: %Schema{type: :integer},
             tasks_executed_count: %Schema{type: :integer},
             tasks_failed_count: %Schema{type: :integer},
             tasks_skipped_count: %Schema{type: :integer},
             tasks_no_source_count: %Schema{type: :integer},
             cacheable_tasks_count: %Schema{type: :integer},
             cache_hit_rate: %Schema{type: :number, nullable: true},
             inserted_at: %Schema{type: :string, format: :"date-time"},
             tasks: %Schema{
               type: :array,
               items: %Schema{
                 type: :object,
                 properties: %{
                   task_path: %Schema{type: :string},
                   task_type: %Schema{type: :string, nullable: true},
                   outcome: %Schema{type: :string},
                   cacheable: %Schema{type: :boolean},
                   duration_ms: %Schema{type: :integer},
                   cache_key: %Schema{type: :string, nullable: true},
                   cache_artifact_size: %Schema{type: :integer, nullable: true},
                   started_at: %Schema{type: :string, format: :"date-time", nullable: true}
                 }
               }
             }
           }
         }},
      not_found: {"Build not found", "application/json", Error},
      forbidden: {"You don't have permission to access this resource", "application/json", Error}
    }
  )

  def get_build(%{assigns: %{selected_project: project}, params: %{build_id: build_id}} = conn, _params) do
    case Gradle.get_build(build_id) do
      {:error, :not_found} ->
        conn
        |> put_status(:not_found)
        |> json(%{message: "Build not found."})

      {:ok, build} ->
        if build.project_id == project.id do
          tasks = Gradle.list_tasks(build_id)

          json(conn, %{
            id: build.id,
            duration_ms: build.duration_ms,
            status: build.status,
            gradle_version: build.gradle_version,
            java_version: build.java_version,
            is_ci: build.is_ci,
            git_branch: build.git_branch,
            git_commit_sha: build.git_commit_sha,
            git_ref: build.git_ref,
            root_project_name: build.root_project_name,
            requested_tasks: build.requested_tasks,
            tasks_local_hit_count: build.tasks_local_hit_count,
            tasks_remote_hit_count: build.tasks_remote_hit_count,
            tasks_up_to_date_count: build.tasks_up_to_date_count,
            tasks_executed_count: build.tasks_executed_count,
            tasks_failed_count: build.tasks_failed_count,
            tasks_skipped_count: build.tasks_skipped_count,
            tasks_no_source_count: build.tasks_no_source_count,
            cacheable_tasks_count: build.cacheable_tasks_count,
            cache_hit_rate: Gradle.cache_hit_rate(build),
            inserted_at: build.inserted_at,
            tasks:
              Enum.map(tasks, fn task ->
                %{
                  task_path: task.task_path,
                  task_type: task.task_type,
                  outcome: task.outcome,
                  cacheable: task.cacheable,
                  duration_ms: task.duration_ms,
                  cache_key: task.cache_key,
                  cache_artifact_size: task.cache_artifact_size,
                  started_at: task.started_at
                }
              end)
          })
        else
          conn
          |> put_status(:not_found)
          |> json(%{message: "Build not found."})
        end
    end
  end
end
