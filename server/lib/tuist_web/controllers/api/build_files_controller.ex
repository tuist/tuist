defmodule TuistWeb.API.BuildFilesController do
  use OpenApiSpex.ControllerSpecs
  use TuistWeb, :controller

  alias OpenApiSpex.Schema
  alias Tuist.Builds
  alias TuistWeb.API.Schemas.Error
  alias TuistWeb.API.Schemas.PaginationMetadata

  plug(TuistWeb.Plugs.InstrumentedCastAndValidate,
    json_render_error_v2: true,
    render_error: TuistWeb.RenderAPIErrorPlug
  )

  plug(TuistWeb.Plugs.LoaderPlug)
  plug(TuistWeb.API.Authorization.AuthorizationPlug, :build)

  tags ["Builds"]

  operation(:index,
    summary: "List compiled files for a given build.",
    operation_id: "listBuildFiles",
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
      target: [
        in: :query,
        type: :string,
        description: "Filter by target name."
      ],
      type: [
        in: :query,
        type: %Schema{
          title: "BuildFileType",
          type: :string,
          enum: ["swift", "c"]
        },
        description: "Filter by file type."
      ],
      sort_by: [
        in: :query,
        type: %Schema{
          title: "BuildFileSortBy",
          type: :string,
          enum: ["compilation_duration", "path"],
          default: "compilation_duration"
        },
        description: "Sort by field."
      ],
      page_size: [
        in: :query,
        type: %Schema{
          title: "BuildFilesIndexPageSize",
          description: "The maximum number of files to return in a single page.",
          type: :integer,
          default: 20,
          minimum: 1,
          maximum: 100
        }
      ],
      page: [
        in: :query,
        type: %Schema{
          title: "BuildFilesIndexPage",
          description: "The page number to return.",
          type: :integer,
          default: 1,
          minimum: 1
        }
      ]
    ],
    responses: %{
      ok:
        {"List of build files", "application/json",
         %Schema{
           type: :object,
           properties: %{
             files: %Schema{
               type: :array,
               items: %Schema{
                 type: :object,
                 properties: %{
                   type: %Schema{type: :string, enum: ["swift", "c"], description: "The file type."},
                   target: %Schema{type: :string, description: "The target name."},
                   project: %Schema{type: :string, description: "The project name."},
                   path: %Schema{type: :string, description: "The file path."},
                   compilation_duration: %Schema{type: :integer, description: "Compilation duration in milliseconds."}
                 },
                 required: [:type, :target, :project, :path, :compilation_duration]
               }
             },
             pagination_metadata: PaginationMetadata
           },
           required: [:files, :pagination_metadata]
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
      nil ->
        conn
        |> put_status(:not_found)
        |> json(%{message: "Build not found."})

      %{project_id: project_id} when project_id == selected_project.id ->
        filters = build_filters(build_id, params)

        {order_by, order_directions} =
          case Map.get(params, :sort_by) do
            "path" -> {[:path], [:asc]}
            _ -> {[:compilation_duration], [:desc]}
          end

        {files, meta} =
          Builds.list_build_files(%{
            filters: filters,
            order_by: order_by,
            order_directions: order_directions,
            page: page,
            page_size: page_size
          })

        json(conn, %{
          files:
            Enum.map(files, fn file ->
              %{
                type: to_string(file.type),
                target: file.target,
                project: file.project,
                path: file.path,
                compilation_duration: file.compilation_duration
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

  defp build_filters(build_id, params) do
    base = [%{field: :build_run_id, op: :==, value: build_id}]

    Enum.reduce([:target, :type], base, fn field, acc ->
      case Map.get(params, field) do
        nil -> acc
        value -> acc ++ [%{field: field, op: :==, value: value}]
      end
    end)
  end
end
