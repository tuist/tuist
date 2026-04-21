defmodule TuistWeb.API.BuildIssuesController do
  use OpenApiSpex.ControllerSpecs
  use TuistWeb, :controller

  alias OpenApiSpex.Schema
  alias Tuist.Builds
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
      ],
      page: [
        in: :query,
        type: %Schema{
          title: "BuildIssuesIndexPage",
          description: "The page number to return.",
          type: :integer,
          default: 1,
          minimum: 1
        }
      ],
      page_size: [
        in: :query,
        type: %Schema{
          title: "BuildIssuesIndexPageSize",
          description: "The maximum number of issues to return in a single page.",
          type: :integer,
          default: 20,
          minimum: 1,
          maximum: 100
        }
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
             },
             pagination_metadata: PaginationMetadata
           },
           required: [:issues, :pagination_metadata]
         }},
      not_found: {"Build not found", "application/json", Error},
      forbidden: {"You don't have permission to access this resource", "application/json", Error}
    }
  )

  def index(
        %{
          assigns: %{selected_project: selected_project},
          params: %{build_id: build_id, page: page, page_size: page_size} = params
        } = conn,
        _params
      ) do
    case Builds.get_build(build_id) do
      {:error, :not_found} ->
        conn
        |> put_status(:not_found)
        |> json(%{message: "Build not found."})

      {:ok, build} ->
        if build.project_id == selected_project.id do
          filters = [%{field: :build_run_id, op: :==, value: build_id}]

          filters =
            if Map.get(params, :type) do
              filters ++ [%{field: :type, op: :==, value: params.type}]
            else
              filters
            end

          filters =
            if Map.get(params, :target) do
              filters ++ [%{field: :target, op: :==, value: params.target}]
            else
              filters
            end

          filters =
            if Map.get(params, :step_type) do
              filters ++ [%{field: :step_type, op: :==, value: params.step_type}]
            else
              filters
            end

          {issues, meta} =
            Builds.list_build_issues_paginated(%{
              filters: filters,
              order_by: [:inserted_at],
              order_directions: [:asc],
              page: page,
              page_size: page_size
            })

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
          conn
          |> put_status(:not_found)
          |> json(%{message: "Build not found."})
        end
    end
  end
end
