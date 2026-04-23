defmodule TuistWeb.API.GradleTasksController do
  use OpenApiSpex.ControllerSpecs
  use TuistWeb, :controller

  alias OpenApiSpex.Schema
  alias Tuist.Gradle
  alias TuistWeb.API.Schemas.Error
  alias TuistWeb.API.Schemas.PaginationMetadata

  plug TuistWeb.Plugs.CastAndValidate,
    json_render_error_v2: true,
    render_error: TuistWeb.RenderAPIErrorPlug

  plug TuistWeb.Plugs.LoaderPlug
  plug TuistWeb.API.Authorization.AuthorizationPlug, :build

  tags ["Gradle"]

  operation(:index,
    summary: "List tasks for a Gradle build.",
    operation_id: "listGradleBuildTasks",
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
        description: "The ID of the Gradle build."
      ],
      outcome: [
        in: :query,
        type: %Schema{
          title: "GradleTaskOutcome",
          type: :string,
          enum: ["local_hit", "remote_hit", "up_to_date", "executed", "failed", "skipped", "no_source"]
        },
        description: "Filter by task outcome."
      ],
      cacheable: [
        in: :query,
        type: :boolean,
        description: "Filter by whether the task is cacheable."
      ],
      page_size: [
        in: :query,
        type: %Schema{
          title: "GradleTasksIndexPageSize",
          description: "The maximum number of tasks to return in a single page.",
          type: :integer,
          default: 20,
          minimum: 1,
          maximum: 100
        }
      ],
      page: [
        in: :query,
        type: %Schema{
          title: "GradleTasksIndexPage",
          description: "The page number to return.",
          type: :integer,
          default: 1,
          minimum: 1
        }
      ]
    ],
    responses: %{
      ok:
        {"List of Gradle build tasks", "application/json",
         %Schema{
           type: :object,
           properties: %{
             tasks: %Schema{
               type: :array,
               items: %Schema{
                 type: :object,
                 properties: %{
                   id: %Schema{type: :string, format: :uuid, description: "The task ID."},
                   task_path: %Schema{type: :string, description: "Task path (e.g., :app:compileKotlin)."},
                   task_type: %Schema{type: :string, nullable: true, description: "Task type class name."},
                   outcome: %Schema{
                     type: :string,
                     enum: ["local_hit", "remote_hit", "up_to_date", "executed", "failed", "skipped", "no_source"],
                     description: "Task outcome."
                   },
                   cacheable: %Schema{type: :boolean, description: "Whether the task is cacheable."},
                   duration_ms: %Schema{type: :integer, description: "Task duration in milliseconds."},
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
                 required: [:id, :task_path, :outcome, :cacheable, :duration_ms]
               }
             },
             pagination_metadata: PaginationMetadata
           },
           required: [:tasks, :pagination_metadata]
         }},
      not_found: {"Build not found", "application/json", Error},
      forbidden: {"You don't have permission to access this resource", "application/json", Error}
    }
  )

  def index(
        %{
          assigns: %{selected_project: selected_project},
          params: %{build_id: build_id, page_size: page_size, page: page} = params
        } = conn,
        _params
      ) do
    case Gradle.get_build(build_id) do
      {:error, :not_found} ->
        conn
        |> put_status(:not_found)
        |> json(%{message: "Build not found."})

      {:ok, %{project_id: project_id}} when project_id == selected_project.id ->
        filters = [%{field: :gradle_build_id, op: :==, value: build_id}]

        filters =
          if Map.get(params, :outcome) do
            filters ++ [%{field: :outcome, op: :==, value: params.outcome}]
          else
            filters
          end

        filters =
          if Map.has_key?(params, :cacheable) do
            filters ++ [%{field: :cacheable, op: :==, value: params.cacheable}]
          else
            filters
          end

        {tasks, meta} =
          Gradle.list_tasks(build_id, %{
            filters: filters,
            order_by: [:duration_ms],
            order_directions: [:desc],
            page: page,
            page_size: page_size
          })

        json(conn, %{
          tasks:
            Enum.map(tasks, fn task ->
              %{
                id: task.id,
                task_path: task.task_path,
                task_type: task.task_type,
                outcome: task.outcome,
                cacheable: task.cacheable,
                duration_ms: task.duration_ms,
                cache_key: task.cache_key,
                cache_artifact_size: task.cache_artifact_size,
                started_at: task.started_at
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

      _build ->
        conn
        |> put_status(:not_found)
        |> json(%{message: "Build not found."})
    end
  end
end
