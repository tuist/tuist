defmodule TuistWeb.API.RunsController do
  alias Tuist.CommandEvents
  alias TuistWeb.API.Schemas.Error
  alias TuistWeb.API.Schemas.Run
  alias TuistWeb.API.EnsureProjectPresencePlug
  alias OpenApiSpex.Schema
  use OpenApiSpex.ControllerSpecs
  use TuistWeb, :controller

  plug(OpenApiSpex.Plug.CastAndValidate,
    json_render_error_v2: true,
    render_error: TuistWeb.RenderAPIErrorPlug
  )

  plug(EnsureProjectPresencePlug)
  plug(TuistWeb.API.Authorization.AuthorizationPlug, :command_event)

  operation(:index,
    summary: "List runs associated with a given project.",
    operation_id: "listRuns",
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
      name: [
        in: :query,
        type: :string,
        description: "The name of the run."
      ],
      git_ref: [
        in: :query,
        type: :string,
        description: "The git ref of the run."
      ],
      git_branch: [
        in: :query,
        type: :string,
        description: "The git branch of the run."
      ],
      git_commit_sha: [
        in: :query,
        type: :string,
        description: "The git commit SHA of the run."
      ],
      page_size: [
        in: :query,
        type: %Schema{
          title: "RunsIndexPageSize",
          description: "The maximum number of runs to return in a single page.",
          type: :integer,
          default: 20,
          minimum: 1,
          maximum: 100
        }
      ],
      page: [
        in: :query,
        type: %Schema{
          title: "RunsIndexPage",
          description: "The page number to return.",
          type: :integer,
          default: 1,
          minimum: 1
        }
      ]
    ],
    responses: %{
      ok:
        {"List of runs", "application/json",
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
      forbidden: {"You don't have permission to access this resource", "application/json", Error}
    }
  )

  def index(
        %{
          params:
            %{
              page_size: page_size,
              page: page
            } = params
        } =
          conn,
        _params
      ) do
    project =
      EnsureProjectPresencePlug.get_project(conn)

    filters =
      [
        %{field: :project_id, op: :==, value: project.id}
      ] ++ filters_from_params(params)

    {command_events, _meta} =
      CommandEvents.list_command_events(%{
        page: page,
        page_size: page_size,
        filters: filters,
        order_by: [:created_at],
        order_directions: [:desc]
      })

    conn
    |> json(%{
      runs:
        command_events
        |> Enum.map(fn event ->
          event
          |> Map.take([
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
          |> Map.put(:url, ~p"/#{project.account.name}/#{project.name}/runs/#{event.id}")
        end)
    })
  end

  defp filters_from_params(params) do
    [:name, :git_ref, :git_branch, :git_commit_sha]
    |> Enum.map(&%{field: &1, op: :==, value: Map.get(params, &1)})
    |> Enum.filter(&(&1.value != nil))
  end
end
