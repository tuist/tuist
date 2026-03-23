defmodule TuistWeb.API.BuildCASOutputsController do
  use OpenApiSpex.ControllerSpecs
  use TuistWeb, :controller

  alias OpenApiSpex.Schema
  alias Tuist.Builds
  alias Tuist.Builds.CASOutput
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
    summary: "List CAS outputs for a given build.",
    operation_id: "listBuildCASOutputs",
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
      operation: [
        in: :query,
        type: %Schema{
          title: "CASOutputOperation",
          type: :string,
          enum: ["download", "upload"]
        },
        description: "Filter by CAS operation type."
      ],
      type: [
        in: :query,
        type: %Schema{
          title: "CASOutputType",
          type: :string,
          enum: CASOutput.valid_types()
        },
        description: "Filter by CAS output type."
      ],
      page_size: [
        in: :query,
        type: %Schema{
          title: "BuildCASOutputsIndexPageSize",
          description: "The maximum number of CAS outputs to return in a single page.",
          type: :integer,
          default: 20,
          minimum: 1,
          maximum: 100
        }
      ],
      page: [
        in: :query,
        type: %Schema{
          title: "BuildCASOutputsIndexPage",
          description: "The page number to return.",
          type: :integer,
          default: 1,
          minimum: 1
        }
      ]
    ],
    responses: %{
      ok:
        {"List of CAS outputs", "application/json",
         %Schema{
           type: :object,
           properties: %{
             outputs: %Schema{
               type: :array,
               items: %Schema{
                 type: :object,
                 properties: %{
                   node_id: %Schema{type: :string, description: "The CAS node identifier."},
                   checksum: %Schema{type: :string, description: "The checksum of the CAS object."},
                   size: %Schema{type: :integer, description: "The size in bytes."},
                   compressed_size: %Schema{type: :integer, description: "The compressed size in bytes."},
                   duration: %Schema{type: :number, description: "The operation duration in milliseconds."},
                   operation: %Schema{type: :string, enum: ["download", "upload"], description: "The CAS operation type."},
                   type: %Schema{
                     type: :string,
                     enum: Enum.map(CASOutput.valid_types(), &String.to_atom/1),
                     description: "The CAS output file type."
                   }
                 },
                 required: [:node_id, :checksum, :size, :compressed_size, :duration, :operation]
               }
             },
             pagination_metadata: PaginationMetadata
           },
           required: [:outputs, :pagination_metadata]
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

        {outputs, meta} =
          Builds.list_cas_outputs(%{
            filters: filters,
            order_by: [:size],
            order_directions: [:desc],
            page: page,
            page_size: page_size
          })

        json(conn, %{
          outputs:
            Enum.map(outputs, fn output ->
              %{
                node_id: output.node_id,
                checksum: output.checksum,
                size: output.size,
                compressed_size: output.compressed_size,
                duration: output.duration,
                operation: to_string(output.operation),
                type: to_string(output.type)
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

    Enum.reduce([:operation, :type], base, fn field, acc ->
      case Map.get(params, field) do
        nil -> acc
        value -> acc ++ [%{field: field, op: :==, value: value}]
      end
    end)
  end
end
