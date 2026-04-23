defmodule TuistWeb.API.SelectiveTestingTargetsController do
  use OpenApiSpex.ControllerSpecs
  use TuistWeb, :controller

  alias OpenApiSpex.Schema
  alias Tuist.CommandEvents
  alias Tuist.Tests
  alias Tuist.Xcode
  alias TuistWeb.API.Schemas.Error
  alias TuistWeb.API.Schemas.PaginationMetadata

  plug TuistWeb.Plugs.CastAndValidate,
    json_render_error_v2: true,
    render_error: TuistWeb.RenderAPIErrorPlug

  plug TuistWeb.Plugs.LoaderPlug
  plug TuistWeb.API.Authorization.AuthorizationPlug, :test

  tags ["Tests"]

  operation(:index,
    summary: "List targets for a test run.",
    operation_id: "listTestTargets",
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
      test_run_id: [
        in: :path,
        schema: %Schema{type: :string, format: :uuid},
        required: true,
        description: "The ID of the test run."
      ],
      hit_status: [
        in: :query,
        type: %Schema{
          title: "SelectiveTestingHitStatus",
          type: :string,
          enum: ["miss", "local", "remote"]
        },
        description: "Filter by selective testing hit status."
      ],
      page: [
        in: :query,
        type: %Schema{
          title: "TestTargetsPage",
          description: "The page number to return.",
          type: :integer,
          default: 1,
          minimum: 1
        }
      ],
      page_size: [
        in: :query,
        type: %Schema{
          title: "TestTargetsPageSize",
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
        {"List of test targets", "application/json",
         %Schema{
           type: :object,
           properties: %{
             targets: %Schema{
               type: :array,
               items: %Schema{
                 type: :object,
                 properties: %{
                   name: %Schema{type: :string, description: "The test target name."},
                   hit_status: %Schema{
                     type: :string,
                     enum: ["miss", "local", "remote"],
                     description: "Selective testing hit status."
                   },
                   hash: %Schema{type: :string, description: "The selective testing hash."}
                 },
                 required: [:name, :hit_status, :hash]
               }
             },
             pagination_metadata: PaginationMetadata
           },
           required: [:targets, :pagination_metadata]
         }},
      not_found: {"Test run not found", "application/json", Error},
      forbidden: {"You don't have permission to access this resource", "application/json", Error}
    }
  )

  def index(
        %{assigns: %{selected_project: selected_project}, params: %{test_run_id: test_run_id} = params} = conn,
        _params
      ) do
    with {:ok, %{project_id: project_id} = test_run} when project_id == selected_project.id <-
           Tests.get_test(test_run_id),
         {:ok, command_event} <- CommandEvents.get_command_event_by_test_run_id(test_run.id) do
      page = params.page
      page_size = params.page_size

      filters =
        case Map.get(params, :hit_status) do
          nil -> []
          hit_status -> [%{field: :selective_testing_hit, op: :==, value: hit_status}]
        end

      flop_params = %{
        filters: filters,
        page: page,
        page_size: page_size
      }

      {analytics, meta} = Xcode.selective_testing_analytics(command_event, flop_params)
      test_modules = Map.get(analytics, :test_modules, [])

      json(conn, %{
        targets:
          Enum.map(test_modules, fn target ->
            %{
              name: target.name,
              hit_status: to_string(target.selective_testing_hit),
              hash: target.selective_testing_hash
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
    else
      _ ->
        conn
        |> put_status(:not_found)
        |> json(%{message: "Test run not found."})
    end
  end
end
