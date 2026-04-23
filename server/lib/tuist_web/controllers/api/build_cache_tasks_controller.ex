defmodule TuistWeb.API.BuildCacheTasksController do
  use OpenApiSpex.ControllerSpecs
  use TuistWeb, :controller

  alias OpenApiSpex.Schema
  alias Tuist.Builds
  alias TuistWeb.API.Schemas.Error
  alias TuistWeb.API.Schemas.PaginationMetadata

  plug TuistWeb.Plugs.CastAndValidate,
    json_render_error_v2: true,
    render_error: TuistWeb.RenderAPIErrorPlug

  plug TuistWeb.Plugs.LoaderPlug
  plug TuistWeb.API.Authorization.AuthorizationPlug, :build

  tags ["Builds"]

  operation(:index,
    summary: "List cacheable tasks for a given build.",
    operation_id: "listBuildCacheTasks",
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
        description: "The ID of the build."
      ],
      status: [
        in: :query,
        type: %Schema{
          title: "CacheTaskStatus",
          type: :string,
          enum: ["hit_local", "hit_remote", "miss"]
        },
        description: "Filter by cache status."
      ],
      type: [
        in: :query,
        type: %Schema{
          title: "CacheTaskType",
          type: :string,
          enum: ["clang", "swift"]
        },
        description: "Filter by task type."
      ],
      page_size: [
        in: :query,
        type: %Schema{
          title: "BuildCacheTasksIndexPageSize",
          description: "The maximum number of cache tasks to return in a single page.",
          type: :integer,
          default: 20,
          minimum: 1,
          maximum: 100
        }
      ],
      page: [
        in: :query,
        type: %Schema{
          title: "BuildCacheTasksIndexPage",
          description: "The page number to return.",
          type: :integer,
          default: 1,
          minimum: 1
        }
      ]
    ],
    responses: %{
      ok:
        {"List of build cache tasks", "application/json",
         %Schema{
           type: :object,
           properties: %{
             tasks: %Schema{
               type: :array,
               items: %Schema{
                 type: :object,
                 properties: %{
                   type: %Schema{type: :string, enum: ["clang", "swift"], description: "The task type."},
                   status: %Schema{
                     type: :string,
                     enum: ["hit_local", "hit_remote", "miss"],
                     description: "The cache status."
                   },
                   key: %Schema{type: :string, description: "The cache key."},
                   read_duration: %Schema{type: :number, nullable: true, description: "Read duration in milliseconds."},
                   write_duration: %Schema{type: :number, nullable: true, description: "Write duration in milliseconds."},
                   description: %Schema{type: :string, nullable: true, description: "Description of the cacheable task."},
                   cas_output_node_ids: %Schema{
                     type: :array,
                     items: %Schema{type: :string},
                     description: "CAS output node IDs associated with this task."
                   }
                 },
                 required: [:type, :status, :key]
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
    case Builds.get_build(build_id) do
      {:error, :not_found} ->
        conn
        |> put_status(:not_found)
        |> json(%{message: "Build not found."})

      {:ok, %{project_id: project_id}} when project_id == selected_project.id ->
        filters = build_filters(build_id, params)

        {:ok, {tasks, meta}} =
          Builds.list_cacheable_tasks(%{
            filters: filters,
            order_by: [:inserted_at],
            order_directions: [:desc],
            page: page,
            page_size: page_size
          })

        json(conn, %{
          tasks:
            Enum.map(tasks, fn task ->
              %{
                type: to_string(task.type),
                status: to_string(task.status),
                key: task.key,
                read_duration: task.read_duration,
                write_duration: task.write_duration,
                description: task.description,
                cas_output_node_ids: task.cas_output_node_ids
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

      {:ok, _build} ->
        conn
        |> put_status(:not_found)
        |> json(%{message: "Build not found."})
    end
  end

  defp build_filters(build_id, params) do
    base = [%{field: :build_run_id, op: :==, value: build_id}]

    Enum.reduce([:status, :type], base, fn field, acc ->
      case Map.get(params, field) do
        nil -> acc
        value -> acc ++ [%{field: field, op: :==, value: value}]
      end
    end)
  end
end
