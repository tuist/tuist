defmodule TuistWeb.API.BuildsController do
  use OpenApiSpex.ControllerSpecs
  use TuistWeb, :controller

  alias OpenApiSpex.Schema
  alias Tuist.Runs
  alias TuistWeb.API.Schemas.Error
  alias TuistWeb.API.Schemas.PaginationMetadata

  plug(OpenApiSpex.Plug.CastAndValidate,
    json_render_error_v2: true,
    render_error: TuistWeb.RenderAPIErrorPlug
  )

  plug(TuistWeb.Plugs.LoaderPlug)
  plug(TuistWeb.API.Authorization.AuthorizationPlug, :build)

  tags ["Builds"]

  operation(:index,
    summary: "List builds associated with a given project.",
    operation_id: "listBuilds",
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
      status: [
        in: :query,
        type: %Schema{
          title: "BuildStatus",
          type: :string,
          enum: ["success", "failure"]
        },
        description: "Filter by build status."
      ],
      category: [
        in: :query,
        type: %Schema{
          title: "BuildCategory",
          type: :string,
          enum: ["clean", "incremental"]
        },
        description: "Filter by build category."
      ],
      scheme: [
        in: :query,
        type: :string,
        description: "Filter by scheme name."
      ],
      configuration: [
        in: :query,
        type: :string,
        description: "Filter by configuration name."
      ],
      git_branch: [
        in: :query,
        type: :string,
        description: "Filter by git branch."
      ],
      page_size: [
        in: :query,
        type: %Schema{
          title: "BuildsIndexPageSize",
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
          title: "BuildsIndexPage",
          description: "The page number to return.",
          type: :integer,
          default: 1,
          minimum: 1
        }
      ]
    ],
    responses: %{
      ok:
        {"List of builds", "application/json",
         %Schema{
           type: :object,
           properties: %{
             builds: %Schema{
               type: :array,
               items: %Schema{
                 type: :object,
                 properties: %{
                   id: %Schema{type: :string, format: :uuid, description: "The build ID."},
                   duration: %Schema{type: :integer, description: "Build duration in milliseconds."},
                   status: %Schema{type: :string, enum: ["success", "failure"], description: "Build status."},
                   category: %Schema{
                     type: :string,
                     enum: ["clean", "incremental"],
                     nullable: true,
                     description: "Build category."
                   },
                   scheme: %Schema{type: :string, nullable: true, description: "The scheme that was built."},
                   configuration: %Schema{type: :string, nullable: true, description: "The configuration used."},
                   xcode_version: %Schema{type: :string, nullable: true, description: "Xcode version."},
                   macos_version: %Schema{type: :string, nullable: true, description: "macOS version."},
                   model_identifier: %Schema{type: :string, nullable: true, description: "Machine model identifier."},
                   is_ci: %Schema{type: :boolean, description: "Whether the build ran on CI."},
                   git_branch: %Schema{type: :string, nullable: true, description: "Git branch."},
                   git_commit_sha: %Schema{type: :string, nullable: true, description: "Git commit SHA."},
                   git_ref: %Schema{type: :string, nullable: true, description: "Git ref."},
                   cacheable_tasks_count: %Schema{type: :integer, description: "Total cacheable tasks."},
                   cacheable_task_local_hits_count: %Schema{type: :integer, description: "Local cache hits."},
                   cacheable_task_remote_hits_count: %Schema{type: :integer, description: "Remote cache hits."},
                   inserted_at: %Schema{type: :string, format: :"date-time", description: "When the build was created."},
                   url: %Schema{type: :string, description: "URL to view the build in the dashboard."}
                 },
                 required: [
                   :id,
                   :duration,
                   :status,
                   :is_ci,
                   :cacheable_tasks_count,
                   :cacheable_task_local_hits_count,
                   :cacheable_task_remote_hits_count,
                   :inserted_at,
                   :url
                 ]
               }
             },
             pagination_metadata: PaginationMetadata
           },
           required: [:builds, :pagination_metadata]
         }},
      forbidden: {"You don't have permission to access this resource", "application/json", Error}
    }
  )

  def index(
        %{assigns: %{selected_project: selected_project}, params: %{page_size: page_size, page: page} = params} = conn,
        _params
      ) do
    filters = build_filters(selected_project.id, params)

    attrs = %{
      filters: filters,
      order_by: [:inserted_at],
      order_directions: [:desc],
      page: page,
      page_size: page_size
    }

    {builds, meta} = Runs.list_build_runs(attrs, preload: [:ran_by_account])

    json(conn, %{
      builds:
        Enum.map(builds, fn build ->
          %{
            id: build.id,
            duration: build.duration,
            status: to_string(build.status),
            category: if(build.category, do: to_string(build.category)),
            scheme: build.scheme,
            configuration: build.configuration,
            xcode_version: build.xcode_version,
            macos_version: build.macos_version,
            model_identifier: build.model_identifier,
            is_ci: build.is_ci,
            git_branch: build.git_branch,
            git_commit_sha: build.git_commit_sha,
            git_ref: build.git_ref,
            cacheable_tasks_count: build.cacheable_tasks_count,
            cacheable_task_local_hits_count: build.cacheable_task_local_hits_count,
            cacheable_task_remote_hits_count: build.cacheable_task_remote_hits_count,
            inserted_at: build.inserted_at,
            url: ~p"/#{selected_project.account.name}/#{selected_project.name}/builds/build-runs/#{build.id}"
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

  operation(:show,
    summary: "Get a build by ID.",
    operation_id: "getBuild",
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
      ]
    ],
    responses: %{
      ok:
        {"Build details", "application/json",
         %Schema{
           type: :object,
           properties: %{
             id: %Schema{type: :string, format: :uuid, description: "The build ID."},
             duration: %Schema{type: :integer, description: "Build duration in milliseconds."},
             status: %Schema{type: :string, enum: ["success", "failure"], description: "Build status."},
             category: %Schema{
               type: :string,
               enum: ["clean", "incremental"],
               nullable: true,
               description: "Build category."
             },
             scheme: %Schema{type: :string, nullable: true, description: "The scheme that was built."},
             configuration: %Schema{type: :string, nullable: true, description: "The configuration used."},
             xcode_version: %Schema{type: :string, nullable: true, description: "Xcode version."},
             macos_version: %Schema{type: :string, nullable: true, description: "macOS version."},
             model_identifier: %Schema{type: :string, nullable: true, description: "Machine model identifier."},
             is_ci: %Schema{type: :boolean, description: "Whether the build ran on CI."},
             git_branch: %Schema{type: :string, nullable: true, description: "Git branch."},
             git_commit_sha: %Schema{type: :string, nullable: true, description: "Git commit SHA."},
             git_ref: %Schema{type: :string, nullable: true, description: "Git ref."},
             cacheable_tasks_count: %Schema{type: :integer, description: "Total cacheable tasks."},
             cacheable_task_local_hits_count: %Schema{type: :integer, description: "Local cache hits."},
             cacheable_task_remote_hits_count: %Schema{type: :integer, description: "Remote cache hits."},
             inserted_at: %Schema{type: :string, format: :"date-time", description: "When the build was created."},
             url: %Schema{type: :string, description: "URL to view the build in the dashboard."}
           },
           required: [
             :id,
             :duration,
             :status,
             :is_ci,
             :cacheable_tasks_count,
             :cacheable_task_local_hits_count,
             :cacheable_task_remote_hits_count,
             :inserted_at,
             :url
           ]
         }},
      not_found: {"Build not found", "application/json", Error},
      forbidden: {"You don't have permission to access this resource", "application/json", Error}
    }
  )

  def show(%{assigns: %{selected_project: selected_project}, params: %{build_id: build_id}} = conn, _params) do
    case Runs.get_build(build_id) do
      nil ->
        conn
        |> put_status(:not_found)
        |> json(%{message: "Build not found."})

      build ->
        if build.project_id == selected_project.id do
          json(conn, %{
            id: build.id,
            duration: build.duration,
            status: to_string(build.status),
            category: if(build.category, do: to_string(build.category)),
            scheme: build.scheme,
            configuration: build.configuration,
            xcode_version: build.xcode_version,
            macos_version: build.macos_version,
            model_identifier: build.model_identifier,
            is_ci: build.is_ci,
            git_branch: build.git_branch,
            git_commit_sha: build.git_commit_sha,
            git_ref: build.git_ref,
            cacheable_tasks_count: build.cacheable_tasks_count,
            cacheable_task_local_hits_count: build.cacheable_task_local_hits_count,
            cacheable_task_remote_hits_count: build.cacheable_task_remote_hits_count,
            inserted_at: build.inserted_at,
            url: ~p"/#{selected_project.account.name}/#{selected_project.name}/builds/build-runs/#{build.id}"
          })
        else
          conn
          |> put_status(:not_found)
          |> json(%{message: "Build not found."})
        end
    end
  end

  defp build_filters(project_id, params) do
    filters = [%{field: :project_id, op: :==, value: project_id}]

    filters =
      if Map.get(params, :status) do
        status_atom = String.to_existing_atom(params.status)
        filters ++ [%{field: :status, op: :==, value: status_atom}]
      else
        filters
      end

    filters =
      if Map.get(params, :category) do
        category_atom = String.to_existing_atom(params.category)
        filters ++ [%{field: :category, op: :==, value: category_atom}]
      else
        filters
      end

    filters =
      if Map.get(params, :scheme) do
        filters ++ [%{field: :scheme, op: :==, value: params.scheme}]
      else
        filters
      end

    filters =
      if Map.get(params, :configuration) do
        filters ++ [%{field: :configuration, op: :==, value: params.configuration}]
      else
        filters
      end

    if Map.get(params, :git_branch) do
      filters ++ [%{field: :git_branch, op: :==, value: params.git_branch}]
    else
      filters
    end
  end
end
