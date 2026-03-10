defmodule TuistWeb.API.BuildIssuesController do
  use OpenApiSpex.ControllerSpecs
  use TuistWeb, :controller

  alias OpenApiSpex.Schema
  alias Tuist.Builds
  alias TuistWeb.API.Schemas.Error

  plug(OpenApiSpex.Plug.CastAndValidate,
    json_render_error_v2: true,
    render_error: TuistWeb.RenderAPIErrorPlug
  )

  plug(TuistWeb.Plugs.LoaderPlug)
  plug(TuistWeb.API.Authorization.AuthorizationPlug, :build)

  tags ["Builds"]

  operation(:index,
    summary: "List build issues for a given build.",
    operation_id: "listBuildIssues",
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
      type: [
        in: :query,
        type: %Schema{
          title: "BuildIssueType",
          type: :string,
          enum: ["warning", "error"]
        },
        description: "Filter by issue type."
      ],
      target: [
        in: :query,
        type: :string,
        description: "Filter by target name."
      ],
      step_type: [
        in: :query,
        type: :string,
        description: "Filter by compilation step type."
      ]
    ],
    responses: %{
      ok:
        {"List of build issues", "application/json",
         %Schema{
           type: :object,
           properties: %{
             issues: %Schema{
               type: :array,
               items: %Schema{
                 type: :object,
                 properties: %{
                   type: %Schema{type: :string, enum: ["warning", "error"], description: "The issue type."},
                   target: %Schema{type: :string, description: "The target name."},
                   project: %Schema{type: :string, description: "The project name."},
                   title: %Schema{type: :string, description: "The issue title."},
                   message: %Schema{type: :string, nullable: true, description: "The detailed message."},
                   signature: %Schema{type: :string, description: "The issue signature."},
                   step_type: %Schema{type: :string, description: "The compilation step type."},
                   path: %Schema{type: :string, nullable: true, description: "The file path."},
                   starting_line: %Schema{type: :integer, description: "The starting line number."},
                   ending_line: %Schema{type: :integer, description: "The ending line number."},
                   starting_column: %Schema{type: :integer, description: "The starting column number."},
                   ending_column: %Schema{type: :integer, description: "The ending column number."}
                 },
                 required: [
                   :type,
                   :target,
                   :project,
                   :title,
                   :signature,
                   :step_type,
                   :starting_line,
                   :ending_line,
                   :starting_column,
                   :ending_column
                 ]
               }
             }
           },
           required: [:issues]
         }},
      not_found: {"Build not found", "application/json", Error},
      forbidden: {"You don't have permission to access this resource", "application/json", Error}
    }
  )

  def index(%{assigns: %{selected_project: selected_project}, params: %{build_id: build_id} = params} = conn, _params) do
    case Builds.get_build(build_id) do
      nil ->
        conn
        |> put_status(:not_found)
        |> json(%{message: "Build not found."})

      build ->
        if build.project_id == selected_project.id do
          issues = Builds.list_build_issues(build_id)

          issues =
            issues
            |> maybe_filter(:type, Map.get(params, :type))
            |> maybe_filter(:target, Map.get(params, :target))
            |> maybe_filter(:step_type, Map.get(params, :step_type))

          json(conn, %{
            issues:
              Enum.map(issues, fn issue ->
                %{
                  type: to_string(issue.type),
                  target: issue.target,
                  project: issue.project,
                  title: issue.title,
                  message: issue.message,
                  signature: issue.signature,
                  step_type: to_string(issue.step_type),
                  path: issue.path,
                  starting_line: issue.starting_line,
                  ending_line: issue.ending_line,
                  starting_column: issue.starting_column,
                  ending_column: issue.ending_column
                }
              end)
          })
        else
          conn
          |> put_status(:not_found)
          |> json(%{message: "Build not found."})
        end
    end
  end

  defp maybe_filter(items, _field, nil), do: items

  defp maybe_filter(items, field, value) do
    Enum.filter(items, fn item -> to_string(Map.get(item, field)) == value end)
  end
end
