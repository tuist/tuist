defmodule TuistWeb.API.BuildsController do
  use OpenApiSpex.ControllerSpecs
  use TuistWeb, :controller

  alias OpenApiSpex.Schema
  alias Tuist.Runs
  alias TuistWeb.API.Schemas.BuildRunRead
  alias TuistWeb.API.Schemas.Error

  plug(OpenApiSpex.Plug.CastAndValidate,
    json_render_error_v2: true,
    render_error: TuistWeb.RenderAPIErrorPlug
  )

  plug(TuistWeb.Plugs.LoaderPlug)
  plug(TuistWeb.API.Authorization.AuthorizationPlug, :build)

  tags(["Builds"])

  operation(:index,
    summary: "List build runs for a project.",
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
        type: :string,
        description: "The status of the build run."
      ],
      category: [
        in: :query,
        type: :string,
        description: "The category of the build run."
      ],
      scheme: [
        in: :query,
        type: :string,
        description: "The scheme used for the build."
      ],
      configuration: [
        in: :query,
        type: :string,
        description: "The build configuration."
      ],
      git_ref: [
        in: :query,
        type: :string,
        description: "The git ref of the build."
      ],
      git_branch: [
        in: :query,
        type: :string,
        description: "The git branch of the build."
      ],
      git_commit_sha: [
        in: :query,
        type: :string,
        description: "The git commit SHA of the build."
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
               items: BuildRunRead
             }
           },
           required: [:builds]
         }},
      unauthorized: {"You need to be authenticated to access this resource", "application/json", Error},
      forbidden: {"You don't have permission to access this resource", "application/json", Error}
    }
  )

  def index(
        %{assigns: %{selected_project: selected_project}, params: %{page_size: page_size, page: page} = params} = conn,
        _params
      ) do
    filters =
      [
        %{field: :project_id, op: :==, value: selected_project.id}
      ] ++ filters_from_params(params)

    {builds, _meta} =
      Runs.list_build_runs(
        %{
          page: page,
          page_size: page_size,
          filters: filters,
          order_by: [:inserted_at],
          order_directions: [:desc]
        },
        preload: [:ran_by_account]
      )

    json(conn, %{
      builds: Enum.map(builds, &build_to_map(&1, selected_project))
    })
  end

  operation(:show,
    summary: "Get a single build run by ID.",
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
        description: "The ID of the build run."
      ]
    ],
    responses: %{
      ok: {"Build details", "application/json", BuildRunRead},
      unauthorized: {"You need to be authenticated to access this resource", "application/json", Error},
      not_found: {"Build not found", "application/json", Error},
      forbidden: {"You don't have permission to access this resource", "application/json", Error}
    }
  )

  def show(%{assigns: %{selected_project: selected_project}} = conn, params) do
    build_id = params[:build_id]

    case Runs.get_build(build_id) do
      nil ->
        conn
        |> put_status(:not_found)
        |> json(%{message: "Build not found"})

      build ->
        build = Tuist.Repo.preload(build, [:project, :ran_by_account])

        if build.project_id == selected_project.id do
          json(conn, build_to_map(build, selected_project))
        else
          conn
          |> put_status(:not_found)
          |> json(%{message: "Build not found"})
        end
    end
  end

  defp filters_from_params(params) do
    []
    |> maybe_add_filter(:status, params[:status])
    |> maybe_add_filter(:category, params[:category])
    |> maybe_add_filter(:scheme, params[:scheme])
    |> maybe_add_filter(:configuration, params[:configuration])
    |> maybe_add_filter(:git_ref, params[:git_ref])
    |> maybe_add_filter(:git_branch, params[:git_branch])
    |> maybe_add_filter(:git_commit_sha, params[:git_commit_sha])
  end

  defp maybe_add_filter(filters, _field, nil), do: filters
  defp maybe_add_filter(filters, field, value), do: [%{field: field, op: :==, value: value} | filters]

  defp build_to_map(build, selected_project) do
    ran_by =
      case build.ran_by_account do
        nil -> nil
        account -> %{handle: account.name}
      end

    %{
      id: build.id,
      duration: build.duration,
      status: Atom.to_string(build.status),
      category: build.category && Atom.to_string(build.category),
      scheme: build.scheme,
      configuration: build.configuration,
      git_branch: build.git_branch,
      git_commit_sha: build.git_commit_sha,
      git_ref: build.git_ref,
      is_ci: build.is_ci,
      xcode_version: build.xcode_version,
      macos_version: build.macos_version,
      model_identifier: build.model_identifier,
      cacheable_tasks_count: build.cacheable_tasks_count,
      cacheable_task_local_hits_count: build.cacheable_task_local_hits_count,
      cacheable_task_remote_hits_count: build.cacheable_task_remote_hits_count,
      url: ~p"/#{selected_project.account.name}/#{selected_project.name}/builds/build-runs/#{build.id}",
      ran_at: to_unix(build.inserted_at),
      ran_by: ran_by
    }
  end

  defp to_unix(%DateTime{} = datetime), do: DateTime.to_unix(datetime)
  defp to_unix(%NaiveDateTime{} = datetime), do: datetime |> DateTime.from_naive!("Etc/UTC") |> DateTime.to_unix()
end
