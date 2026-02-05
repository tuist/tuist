defmodule TuistWeb.API.GradleController do
  use OpenApiSpex.ControllerSpecs
  use TuistWeb, :controller

  alias OpenApiSpex.Schema
  alias Tuist.Gradle
  alias Tuist.Gradle.Analytics
  alias TuistWeb.API.Schemas.Error

  plug(OpenApiSpex.Plug.CastAndValidate,
    json_render_error_v2: true,
    render_error: TuistWeb.RenderAPIErrorPlug
  )

  plug(TuistWeb.Plugs.LoaderPlug)
  plug(TuistWeb.API.Authorization.AuthorizationPlug, :gradle)

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
           duration_ms: %Schema{type: :integer, description: "Build duration in milliseconds."},
           status: %Schema{type: :string, enum: ["success", "failure", "cancelled"], description: "Build status."},
           gradle_version: %Schema{type: :string, nullable: true, description: "Gradle version."},
           java_version: %Schema{type: :string, nullable: true, description: "Java version."},
           is_ci: %Schema{type: :boolean, description: "Whether the build ran on CI."},
           git_branch: %Schema{type: :string, nullable: true, description: "Git branch."},
           git_commit_sha: %Schema{type: :string, nullable: true, description: "Git commit SHA."},
           git_ref: %Schema{type: :string, nullable: true, description: "Git ref."},
           avoidance_savings_ms: %Schema{type: :integer, nullable: true, description: "Estimated time saved by avoidance."},
           tasks: %Schema{
             type: :array,
             items: %Schema{
               type: :object,
               properties: %{
                 task_path: %Schema{type: :string, description: "Task path (e.g., :app:compileKotlin)."},
                 task_type: %Schema{type: :string, nullable: true, description: "Task type class name."},
                 outcome: %Schema{
                   type: :string,
                   enum: ["from_cache", "up_to_date", "executed", "failed", "skipped", "no_source"],
                   description: "Task outcome."
                 },
                 cacheable: %Schema{type: :boolean, description: "Whether the task is cacheable."},
                 duration_ms: %Schema{type: :integer, nullable: true, description: "Task duration in milliseconds."},
                 cache_key: %Schema{type: :string, nullable: true, description: "Cache key for cacheable tasks."},
                 cache_artifact_size: %Schema{type: :integer, nullable: true, description: "Size of cache artifact in bytes."}
               },
               required: [:task_path, :outcome]
             }
           }
         },
         required: [:duration_ms, :status]
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

  def create_build(%{assigns: %{selected_project: project, selected_account: account}, body_params: body} = conn, _params) do
    tasks =
      (body[:tasks] || [])
      |> Enum.map(fn task ->
        %{
          task_path: task.task_path,
          task_type: task[:task_type],
          outcome: task.outcome,
          cacheable: task[:cacheable] || false,
          duration_ms: task[:duration_ms] || 0,
          cache_key: task[:cache_key],
          cache_artifact_size: task[:cache_artifact_size]
        }
      end)

    attrs = %{
      project_id: project.id,
      account_id: account.id,
      duration_ms: body.duration_ms,
      status: body.status,
      gradle_version: body[:gradle_version],
      java_version: body[:java_version],
      is_ci: body[:is_ci] || false,
      git_branch: body[:git_branch],
      git_commit_sha: body[:git_commit_sha],
      git_ref: body[:git_ref],
      avoidance_savings_ms: body[:avoidance_savings_ms] || 0,
      tasks: tasks
    }

    case Gradle.create_build(attrs) do
      {:ok, build_id} ->
        conn
        |> put_status(:created)
        |> json(%{id: build_id})

      {:error, reason} ->
        conn
        |> put_status(:bad_request)
        |> json(%{message: "Failed to create build: #{inspect(reason)}"})
    end
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
      limit: [
        in: :query,
        type: %Schema{type: :integer, default: 50, minimum: 1, maximum: 100},
        description: "Maximum number of builds to return."
      ],
      offset: [
        in: :query,
        type: %Schema{type: :integer, default: 0, minimum: 0},
        description: "Number of builds to skip."
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
                   tasks_from_cache_count: %Schema{type: :integer},
                   tasks_up_to_date_count: %Schema{type: :integer},
                   tasks_executed_count: %Schema{type: :integer},
                   cacheable_tasks_count: %Schema{type: :integer},
                   cache_hit_rate: %Schema{type: :number, nullable: true},
                   inserted_at: %Schema{type: :string, format: :"date-time"}
                 }
               }
             }
           },
           required: [:builds]
         }},
      forbidden: {"You don't have permission to access this resource", "application/json", Error}
    }
  )

  def list_builds(%{assigns: %{selected_project: project}, params: params} = conn, _params) do
    limit = Map.get(params, :limit, 50)
    offset = Map.get(params, :offset, 0)

    builds = Gradle.list_builds(project.id, limit: limit, offset: offset)

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
            tasks_from_cache_count: build.tasks_from_cache_count,
            tasks_up_to_date_count: build.tasks_up_to_date_count,
            tasks_executed_count: build.tasks_executed_count,
            cacheable_tasks_count: build.cacheable_tasks_count,
            cache_hit_rate: calculate_cache_hit_rate(build),
            inserted_at: build.inserted_at
          }
        end)
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
             tasks_from_cache_count: %Schema{type: :integer},
             tasks_up_to_date_count: %Schema{type: :integer},
             tasks_executed_count: %Schema{type: :integer},
             tasks_failed_count: %Schema{type: :integer},
             tasks_skipped_count: %Schema{type: :integer},
             tasks_no_source_count: %Schema{type: :integer},
             cacheable_tasks_count: %Schema{type: :integer},
             avoidance_savings_ms: %Schema{type: :integer},
             cache_hit_rate: %Schema{type: :number, nullable: true},
             avoidance_rate: %Schema{type: :number, nullable: true},
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
                   cache_artifact_size: %Schema{type: :integer, nullable: true}
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
      nil ->
        conn
        |> put_status(:not_found)
        |> json(%{message: "Build not found."})

      build ->
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
            tasks_from_cache_count: build.tasks_from_cache_count,
            tasks_up_to_date_count: build.tasks_up_to_date_count,
            tasks_executed_count: build.tasks_executed_count,
            tasks_failed_count: build.tasks_failed_count,
            tasks_skipped_count: build.tasks_skipped_count,
            tasks_no_source_count: build.tasks_no_source_count,
            cacheable_tasks_count: build.cacheable_tasks_count,
            avoidance_savings_ms: build.avoidance_savings_ms,
            cache_hit_rate: calculate_cache_hit_rate(build),
            avoidance_rate: calculate_avoidance_rate(build),
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
                  cache_artifact_size: task.cache_artifact_size
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

  operation(:analytics,
    summary: "Get Gradle cache analytics for a project.",
    operation_id: "getGradleAnalytics",
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
      start_date: [
        in: :query,
        type: %Schema{type: :string, format: :date},
        description: "Start date for analytics (default: 30 days ago)."
      ],
      end_date: [
        in: :query,
        type: %Schema{type: :string, format: :date},
        description: "End date for analytics (default: today)."
      ]
    ],
    responses: %{
      ok:
        {"Gradle analytics", "application/json",
         %Schema{
           type: :object,
           properties: %{
             cache_hit_rate: %Schema{
               type: :object,
               properties: %{
                 avg: %Schema{type: :number},
                 p50: %Schema{type: :number},
                 p90: %Schema{type: :number},
                 p99: %Schema{type: :number},
                 trend: %Schema{type: :number}
               }
             },
             task_outcomes: %Schema{
               type: :object,
               properties: %{
                 from_cache: %Schema{type: :integer},
                 up_to_date: %Schema{type: :integer},
                 executed: %Schema{type: :integer},
                 failed: %Schema{type: :integer},
                 skipped: %Schema{type: :integer},
                 no_source: %Schema{type: :integer}
               }
             },
             cache_events: %Schema{
               type: :object,
               properties: %{
                 uploads: %Schema{
                   type: :object,
                   properties: %{
                     total_size: %Schema{type: :integer},
                     count: %Schema{type: :integer},
                     trend: %Schema{type: :number}
                   }
                 },
                 downloads: %Schema{
                   type: :object,
                   properties: %{
                     total_size: %Schema{type: :integer},
                     count: %Schema{type: :integer},
                     trend: %Schema{type: :number}
                   }
                 }
               }
             }
           }
         }},
      forbidden: {"You don't have permission to access this resource", "application/json", Error}
    }
  )

  def analytics(%{assigns: %{selected_project: project}, params: params} = conn, _params) do
    start_datetime = parse_date(params[:start_date], DateTime.add(DateTime.utc_now(), -30, :day))
    end_datetime = parse_date(params[:end_date], DateTime.utc_now())

    opts = [
      start_datetime: start_datetime,
      end_datetime: end_datetime
    ]

    [hit_rate_analytics, hit_rate_p99, hit_rate_p90, hit_rate_p50, task_breakdown, cache_events] =
      Analytics.combined_gradle_analytics(project.id, opts)

    json(conn, %{
      cache_hit_rate: %{
        avg: hit_rate_analytics.avg_hit_rate,
        p50: hit_rate_p50.total_percentile_hit_rate,
        p90: hit_rate_p90.total_percentile_hit_rate,
        p99: hit_rate_p99.total_percentile_hit_rate,
        trend: hit_rate_analytics.trend
      },
      task_outcomes: task_breakdown,
      cache_events: %{
        uploads: %{
          total_size: cache_events.uploads.total_size,
          count: cache_events.uploads.count,
          trend: cache_events.uploads.trend
        },
        downloads: %{
          total_size: cache_events.downloads.total_size,
          count: cache_events.downloads.count,
          trend: cache_events.downloads.trend
        }
      }
    })
  end

  defp calculate_cache_hit_rate(build) do
    total = (build.tasks_from_cache_count || 0) + (build.tasks_executed_count || 0)

    if total > 0 do
      Float.round((build.tasks_from_cache_count || 0) / total * 100.0, 1)
    else
      nil
    end
  end

  defp calculate_avoidance_rate(build) do
    total =
      (build.tasks_from_cache_count || 0) + (build.tasks_up_to_date_count || 0) +
        (build.tasks_executed_count || 0) + (build.tasks_failed_count || 0) +
        (build.tasks_skipped_count || 0) + (build.tasks_no_source_count || 0)

    if total > 0 do
      avoided = (build.tasks_from_cache_count || 0) + (build.tasks_up_to_date_count || 0)
      Float.round(avoided / total * 100.0, 1)
    else
      nil
    end
  end

  defp parse_date(nil, default), do: default

  defp parse_date(date_string, default) do
    case Date.from_iso8601(date_string) do
      {:ok, date} -> DateTime.new!(date, ~T[00:00:00], "Etc/UTC")
      _ -> default
    end
  end
end
