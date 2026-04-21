defmodule TuistWeb.API.BuildTargetsController do
  use OpenApiSpex.ControllerSpecs
  use TuistWeb, :controller

  alias OpenApiSpex.Schema
  alias Tuist.Builds
  alias TuistWeb.API.Schemas.Error
  alias TuistWeb.API.Schemas.PaginationMetadata

  plug(TuistWeb.Plugs.CastAndValidate,
    json_render_error_v2: true,
    render_error: TuistWeb.RenderAPIErrorPlug
  )

  plug(TuistWeb.Plugs.LoaderPlug)
  plug(TuistWeb.API.Authorization.AuthorizationPlug, :build)

  tags ["Builds"]

  operation(:index,
    summary: "List build targets for a given build.",
    operation_id: "listBuildTargets",
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
          title: "BuildTargetStatus",
          type: :string,
          enum: ["success", "failure"]
        },
        description: "Filter by target status."
      ],
      page_size: [
        in: :query,
        type: %Schema{
          title: "BuildTargetsIndexPageSize",
          description: "The maximum number of targets to return in a single page.",
          type: :integer,
          default: 20,
          minimum: 1,
          maximum: 100
        }
      ],
      page: [
        in: :query,
        type: %Schema{
          title: "BuildTargetsIndexPage",
          description: "The page number to return.",
          type: :integer,
          default: 1,
          minimum: 1
        }
      ]
    ],
    responses: %{
      ok:
        {"List of build targets", "application/json",
         %Schema{
           type: :object,
           properties: %{
             targets: %Schema{
               type: :array,
               items: %Schema{
                 type: :object,
                 properties: %{
                   name: %Schema{type: :string, description: "The target name."},
                   project: %Schema{type: :string, description: "The target's project name."},
                   build_duration: %Schema{type: :integer, description: "Build duration in milliseconds."},
                   compilation_duration: %Schema{type: :integer, description: "Compilation duration in milliseconds."},
                   status: %Schema{type: :string, enum: ["success", "failure"], description: "Target build status."}
                 },
                 required: [:name, :project, :build_duration, :compilation_duration, :status]
               }
             },
             pagination_metadata: PaginationMetadata
           },
           required: [:targets, :pagination_metadata]
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
        filters = [%{field: :build_run_id, op: :==, value: build_id}]

        filters =
          if Map.get(params, :status) do
            filters ++ [%{field: :status, op: :==, value: params.status}]
          else
            filters
          end

        {targets, meta} =
          Builds.list_build_targets(%{
            filters: filters,
            order_by: [:build_duration],
            order_directions: [:desc],
            page: page,
            page_size: page_size
          })

        json(conn, %{
          targets:
            Enum.map(targets, fn target ->
              %{
                name: target.name,
                project: target.project,
                build_duration: target.build_duration,
                compilation_duration: target.compilation_duration,
                status: to_string(target.status)
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
end
