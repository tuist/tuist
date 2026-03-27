defmodule TuistWeb.API.ModuleCacheTargetsController do
  use OpenApiSpex.ControllerSpecs
  use TuistWeb, :controller

  alias OpenApiSpex.Schema
  alias Tuist.CommandEvents
  alias Tuist.Xcode
  alias TuistWeb.API.Schemas.Error
  alias TuistWeb.API.Schemas.PaginationMetadata

  plug(TuistWeb.Plugs.CastAndValidate,
    json_render_error_v2: true,
    render_error: TuistWeb.RenderAPIErrorPlug
  )

  plug(TuistWeb.Plugs.LoaderPlug)
  plug(TuistWeb.API.Authorization.AuthorizationPlug, :run)

  tags ["Runs"]

  @subhash_keys ~w(sources resources copy_files core_data_models target_scripts environment headers deployment_target info_plist entitlements dependencies project_settings target_settings buildable_folders external)a

  operation(:index,
    summary: "List module cache targets for a run.",
    operation_id: "listModuleCacheTargets",
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
      run_id: [
        in: :path,
        schema: %Schema{type: :string, format: :uuid},
        required: true,
        description: "The ID of the command run."
      ],
      cache_status: [
        in: :query,
        type: %Schema{
          title: "CacheStatus",
          type: :string,
          enum: ["miss", "local", "remote"]
        },
        description: "Filter by cache status."
      ],
      page: [
        in: :query,
        type: %Schema{
          title: "ModuleCacheTargetsPage",
          description: "The page number to return.",
          type: :integer,
          default: 1,
          minimum: 1
        }
      ],
      page_size: [
        in: :query,
        type: %Schema{
          title: "ModuleCacheTargetsPageSize",
          description: "The maximum number of targets to return in a single page.",
          type: :integer,
          default: 20,
          minimum: 1,
          maximum: 100
        }
      ]
    ],
    responses: %{
      ok:
        {"List of module cache targets", "application/json",
         %Schema{
           type: :object,
           properties: %{
             targets: %Schema{
               type: :array,
               items: %Schema{
                 type: :object,
                 properties: %{
                   name: %Schema{type: :string, description: "The target name."},
                   cache_status: %Schema{
                     type: :string,
                     nullable: true,
                     enum: ["miss", "local", "remote"],
                     description: "The cache status."
                   },
                   cache_hash: %Schema{type: :string, nullable: true, description: "The cache hash."},
                   product: %Schema{type: :string, nullable: true, description: "The product type."},
                   bundle_id: %Schema{type: :string, nullable: true, description: "The bundle identifier."},
                   product_name: %Schema{type: :string, nullable: true, description: "The product name."},
                   subhashes: %Schema{
                     type: :object,
                     additionalProperties: %Schema{type: :string},
                     description: "Non-nil hash components."
                   }
                 },
                 required: [:name]
               }
             },
             pagination_metadata: PaginationMetadata
           },
           required: [:targets, :pagination_metadata]
         }},
      not_found: {"Run not found", "application/json", Error},
      forbidden: {"You don't have permission to access this resource", "application/json", Error}
    }
  )

  def index(%{assigns: %{selected_project: selected_project}, params: %{run_id: run_id} = params} = conn, _params) do
    case CommandEvents.get_command_event_by_id(run_id) do
      {:ok, %{project_id: project_id} = event}
      when project_id == selected_project.id ->
        page = Map.get(params, :page, 1)
        page_size = Map.get(params, :page_size, 20)

        filters =
          case Map.get(params, :cache_status) do
            nil -> []
            cache_status -> [%{field: :binary_cache_hit, op: :==, value: cache_status}]
          end

        flop_params = %{
          filters: filters,
          page: page,
          page_size: page_size
        }

        {analytics, meta} = Xcode.binary_cache_analytics(event, flop_params)
        targets = Map.get(analytics, :cacheable_targets, [])

        json(conn, %{
          targets:
            Enum.map(targets, fn target ->
              cache_status =
                case target.binary_cache_hit do
                  nil -> nil
                  "" -> nil
                  value -> to_string(value)
                end

              %{
                name: target.name,
                cache_status: cache_status,
                cache_hash: target.binary_cache_hash,
                product: target.product,
                bundle_id: target.bundle_id,
                product_name: target.product_name,
                subhashes: build_subhashes(target)
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

      _error ->
        conn
        |> put_status(:not_found)
        |> json(%{message: "Run not found."})
    end
  end

  defp build_subhashes(target) do
    Enum.reduce(@subhash_keys, %{}, fn key, acc ->
      field = :"#{key}_hash"
      value = Map.get(target, field)

      if is_nil(value) or value == "" do
        acc
      else
        Map.put(acc, key, value)
      end
    end)
  end
end
