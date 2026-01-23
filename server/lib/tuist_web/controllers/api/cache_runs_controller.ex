defmodule TuistWeb.API.CacheRunsController do
  use OpenApiSpex.ControllerSpecs
  use TuistWeb, :controller

  alias OpenApiSpex.Schema
  alias Tuist.CommandEvents
  alias TuistWeb.API.Schemas.Error
  alias TuistWeb.API.Schemas.Run

  plug(OpenApiSpex.Plug.CastAndValidate,
    json_render_error_v2: true,
    render_error: TuistWeb.RenderAPIErrorPlug
  )

  plug(TuistWeb.Plugs.LoaderPlug)
  plug(TuistWeb.API.Authorization.AuthorizationPlug, :run)

  tags(["CacheRuns"])

  operation(:index,
    summary: "List cache runs for a project.",
    operation_id: "listCacheRuns",
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
        description: "The git ref of the cache run."
      ],
      git_branch: [
        in: :query,
        type: :string,
        description: "The git branch of the cache run."
      ],
      git_commit_sha: [
        in: :query,
        type: :string,
        description: "The git commit SHA of the cache run."
      ],
      page_size: [
        in: :query,
        type: %Schema{
          title: "CacheRunsIndexPageSize",
          description: "The maximum number of cache runs to return in a single page.",
          type: :integer,
          default: 20,
          minimum: 1,
          maximum: 100
        }
      ],
      page: [
        in: :query,
        type: %Schema{
          title: "CacheRunsIndexPage",
          description: "The page number to return.",
          type: :integer,
          default: 1,
          minimum: 1
        }
      ]
    ],
    responses: %{
      ok:
        {"List of cache runs", "application/json",
         %Schema{
           type: :object,
           properties: %{
             runs: %Schema{
               type: :array,
               items: Run
             }
           },
           required: [:runs]
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
        %{field: :project_id, op: :==, value: selected_project.id},
        %{field: :name, op: :==, value: "cache"}
      ] ++ filters_from_params(params)

    {command_events, _meta} =
      CommandEvents.list_command_events(%{
        page: page,
        page_size: page_size,
        filters: filters,
        order_by: [:ran_at],
        order_directions: [:desc]
      })

    json(conn, %{
      runs: Enum.map(command_events, &run_to_map(&1, selected_project))
    })
  end

  operation(:show,
    summary: "Get a single cache run by ID.",
    operation_id: "getCacheRun",
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
        type: :string,
        required: true,
        description: "The ID of the cache run."
      ]
    ],
    responses: %{
      ok: {"Cache run details", "application/json", Run},
      unauthorized: {"You need to be authenticated to access this resource", "application/json", Error},
      not_found: {"Cache run not found", "application/json", Error},
      forbidden: {"You don't have permission to access this resource", "application/json", Error}
    }
  )

  def show(%{assigns: %{selected_project: selected_project}} = conn, params) do
    run_id = params[:run_id]

    with {:ok, command_event} <- CommandEvents.get_command_event_by_id(run_id),
         {:ok, project} <- CommandEvents.get_project_for_command_event(command_event),
         true <- project.id == selected_project.id,
         true <- command_event.name == "cache" do
      json(conn, run_to_map(command_event, selected_project))
    else
      _ ->
        conn
        |> put_status(:not_found)
        |> json(%{message: "Cache run not found"})
    end
  end

  defp filters_from_params(params) do
    []
    |> maybe_add_filter(:git_ref, params[:git_ref])
    |> maybe_add_filter(:git_branch, params[:git_branch])
    |> maybe_add_filter(:git_commit_sha, params[:git_commit_sha])
  end

  defp maybe_add_filter(filters, _field, nil), do: filters
  defp maybe_add_filter(filters, field, value), do: [%{field: field, op: :==, value: value} | filters]

  defp run_to_map(event, selected_project) do
    ran_by =
      case CommandEvents.get_user_for_command_event(event) do
        {:ok, user} ->
          user = Tuist.Repo.preload(user, :account)
          %{handle: user.account.name}

        {:error, :not_found} ->
          nil
      end

    event
    |> Map.take([
      :legacy_id,
      :id,
      :name,
      :duration,
      :subcommand,
      :command_arguments,
      :tuist_version,
      :swift_version,
      :macos_version,
      :status,
      :git_ref,
      :git_commit_sha,
      :git_branch,
      :cacheable_targets,
      :local_cache_target_hits,
      :remote_cache_target_hits,
      :test_targets,
      :local_test_target_hits,
      :remote_test_target_hits,
      :preview_id
    ])
    |> Map.put(:id, event.legacy_id)
    |> Map.put(:uuid, event.id)
    |> Map.delete(:legacy_id)
    |> Map.put(
      :url,
      ~p"/#{selected_project.account.name}/#{selected_project.name}/runs/#{event.id}"
    )
    |> Map.put(
      :ran_at,
      event.created_at |> DateTime.from_naive!("Etc/UTC") |> DateTime.to_unix()
    )
    |> Map.put(:ran_by, ran_by)
  end
end
