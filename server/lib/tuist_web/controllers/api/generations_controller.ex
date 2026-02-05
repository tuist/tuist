defmodule TuistWeb.API.GenerationsController do
  use OpenApiSpex.ControllerSpecs
  use TuistWeb, :controller

  alias OpenApiSpex.Schema
  alias Tuist.CommandEvents
  alias TuistWeb.API.Schemas.Error
  alias TuistWeb.API.Schemas.PaginationMetadata

  plug(OpenApiSpex.Plug.CastAndValidate,
    json_render_error_v2: true,
    render_error: TuistWeb.RenderAPIErrorPlug
  )

  plug(TuistWeb.Plugs.LoaderPlug)
  plug(TuistWeb.API.Authorization.AuthorizationPlug, :run)

  tags ["Generations"]

  operation(:index,
    summary: "List generations associated with a given project.",
    operation_id: "listGenerations",
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
      git_ref: [
        in: :query,
        type: :string,
        description: "Filter by git ref."
      ],
      git_branch: [
        in: :query,
        type: :string,
        description: "Filter by git branch."
      ],
      git_commit_sha: [
        in: :query,
        type: :string,
        description: "Filter by git commit SHA."
      ],
      page_size: [
        in: :query,
        type: %Schema{
          title: "GenerationsIndexPageSize",
          description: "The maximum number of generations to return in a single page.",
          type: :integer,
          default: 20,
          minimum: 1,
          maximum: 100
        }
      ],
      page: [
        in: :query,
        type: %Schema{
          title: "GenerationsIndexPage",
          description: "The page number to return.",
          type: :integer,
          default: 1,
          minimum: 1
        }
      ]
    ],
    responses: %{
      ok:
        {"List of generations", "application/json",
         %Schema{
           type: :object,
           properties: %{
             generations: %Schema{
               type: :array,
               items: %Schema{
                 type: :object,
                 properties: %{
                   id: %Schema{type: :string, format: :uuid, description: "The generation ID."},
                   duration: %Schema{type: :integer, description: "Generation duration in milliseconds."},
                   status: %Schema{type: :string, enum: ["success", "failure"], description: "Generation status."},
                   tuist_version: %Schema{type: :string, nullable: true, description: "Tuist version used."},
                   swift_version: %Schema{type: :string, nullable: true, description: "Swift version used."},
                   macos_version: %Schema{type: :string, nullable: true, description: "macOS version."},
                   is_ci: %Schema{type: :boolean, description: "Whether the generation ran on CI."},
                   git_branch: %Schema{type: :string, nullable: true, description: "Git branch."},
                   git_commit_sha: %Schema{type: :string, nullable: true, description: "Git commit SHA."},
                   git_ref: %Schema{type: :string, nullable: true, description: "Git ref."},
                   cacheable_targets: %Schema{
                     type: :array,
                     items: %Schema{type: :string},
                     description: "Cacheable targets."
                   },
                   local_cache_target_hits: %Schema{
                     type: :array,
                     items: %Schema{type: :string},
                     description: "Local cache target hits."
                   },
                   remote_cache_target_hits: %Schema{
                     type: :array,
                     items: %Schema{type: :string},
                     description: "Remote cache target hits."
                   },
                   command_arguments: %Schema{type: :string, nullable: true, description: "Command arguments used."},
                   ran_at: %Schema{type: :integer, description: "Unix timestamp when the generation ran."},
                   url: %Schema{type: :string, description: "URL to view the generation in the dashboard."},
                   ran_by: %Schema{
                     type: :object,
                     nullable: true,
                     description: "The account that triggered the generation.",
                     properties: %{
                       handle: %Schema{type: :string, description: "The handle of the account."}
                     }
                   }
                 },
                 required: [
                   :id,
                   :duration,
                   :status,
                   :is_ci,
                   :ran_at,
                   :url
                 ]
               }
             },
             pagination_metadata: PaginationMetadata
           },
           required: [:generations, :pagination_metadata]
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
        %{field: :project_id, op: :==, value: selected_project.id},
        %{field: :name, op: :==, value: "generate"}
      ] ++ filters_from_params(params)

    {command_events, meta} =
      CommandEvents.list_command_events(%{
        page: page,
        page_size: page_size,
        filters: filters,
        order_by: [:ran_at],
        order_directions: [:desc]
      })

    json(conn, %{
      generations:
        Enum.map(command_events, fn event ->
          ran_by =
            if event.user_account_name,
              do: %{handle: event.user_account_name},
              else: nil

          event
          |> Map.take([
            :id,
            :duration,
            :tuist_version,
            :swift_version,
            :macos_version,
            :git_ref,
            :git_commit_sha,
            :git_branch,
            :command_arguments,
            :cacheable_targets,
            :local_cache_target_hits,
            :remote_cache_target_hits
          ])
          |> Map.put(:status, status_to_string(event.status))
          |> Map.put(:is_ci, event.is_ci)
          |> Map.put(
            :url,
            ~p"/#{selected_project.account.name}/#{selected_project.name}/runs/#{event.id}"
          )
          |> Map.put(
            :ran_at,
            event.created_at |> DateTime.from_naive!("Etc/UTC") |> DateTime.to_unix()
          )
          |> Map.put(:ran_by, ran_by)
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

  operation(:show,
    summary: "Get a generation by ID.",
    operation_id: "getGeneration",
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
      generation_id: [
        in: :path,
        schema: %Schema{type: :string, format: :uuid},
        required: true,
        description: "The ID of the generation."
      ]
    ],
    responses: %{
      ok:
        {"Generation details", "application/json",
         %Schema{
           type: :object,
           properties: %{
             id: %Schema{type: :string, format: :uuid, description: "The generation ID."},
             duration: %Schema{type: :integer, description: "Generation duration in milliseconds."},
             status: %Schema{type: :string, enum: ["success", "failure"], description: "Generation status."},
             tuist_version: %Schema{type: :string, nullable: true, description: "Tuist version used."},
             swift_version: %Schema{type: :string, nullable: true, description: "Swift version used."},
             macos_version: %Schema{type: :string, nullable: true, description: "macOS version."},
             is_ci: %Schema{type: :boolean, description: "Whether the generation ran on CI."},
             git_branch: %Schema{type: :string, nullable: true, description: "Git branch."},
             git_commit_sha: %Schema{type: :string, nullable: true, description: "Git commit SHA."},
             git_ref: %Schema{type: :string, nullable: true, description: "Git ref."},
             command_arguments: %Schema{type: :string, nullable: true, description: "Command arguments used."},
             cacheable_targets: %Schema{type: :array, items: %Schema{type: :string}, description: "Cacheable targets."},
             local_cache_target_hits: %Schema{
               type: :array,
               items: %Schema{type: :string},
               description: "Local cache target hits."
             },
             remote_cache_target_hits: %Schema{
               type: :array,
               items: %Schema{type: :string},
               description: "Remote cache target hits."
             },
             ran_at: %Schema{type: :integer, description: "Unix timestamp when the generation ran."},
             url: %Schema{type: :string, description: "URL to view the generation in the dashboard."}
           },
           required: [
             :id,
             :duration,
             :status,
             :is_ci,
             :ran_at,
             :url
           ]
         }},
      not_found: {"Generation not found", "application/json", Error},
      forbidden: {"You don't have permission to access this resource", "application/json", Error}
    }
  )

  def show(%{assigns: %{selected_project: selected_project}, params: %{generation_id: generation_id}} = conn, _params) do
    case CommandEvents.get_command_event_by_id(generation_id) do
      {:ok, event} ->
        if event.project_id == selected_project.id and event.name == "generate" do
          json(conn, %{
            id: event.id,
            duration: event.duration,
            status: status_to_string(event.status),
            tuist_version: event.tuist_version,
            swift_version: event.swift_version,
            macos_version: event.macos_version,
            is_ci: event.is_ci,
            git_branch: event.git_branch,
            git_commit_sha: event.git_commit_sha,
            git_ref: event.git_ref,
            command_arguments: event.command_arguments,
            cacheable_targets: event.cacheable_targets,
            local_cache_target_hits: event.local_cache_target_hits,
            remote_cache_target_hits: event.remote_cache_target_hits,
            ran_at: event.created_at |> DateTime.from_naive!("Etc/UTC") |> DateTime.to_unix(),
            url: ~p"/#{selected_project.account.name}/#{selected_project.name}/runs/#{event.id}"
          })
        else
          conn
          |> put_status(:not_found)
          |> json(%{message: "Generation not found."})
        end

      {:error, :not_found} ->
        conn
        |> put_status(:not_found)
        |> json(%{message: "Generation not found."})
    end
  end

  defp filters_from_params(params) do
    [:git_ref, :git_branch, :git_commit_sha]
    |> Enum.map(&%{field: &1, op: :==, value: Map.get(params, &1)})
    |> Enum.filter(&(&1.value != nil))
  end

  defp status_to_string(0), do: "success"
  defp status_to_string(1), do: "failure"
  defp status_to_string(nil), do: "success"
  defp status_to_string(status) when is_atom(status), do: Atom.to_string(status)
  defp status_to_string(status), do: to_string(status)
end
