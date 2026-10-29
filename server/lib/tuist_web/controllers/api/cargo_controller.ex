defmodule TuistWeb.API.CargoController do
  use OpenApiSpex.ControllerSpecs
  use TuistWeb, :controller

  alias OpenApiSpex.Schema
  alias Tuist.Cargo
  alias Tuist.Cargo.CacheDetails
  alias Tuist.Cargo.CacheMetrics
  alias Tuist.Cargo.Query
  alias Tuist.Projects
  alias Tuist.VCS.RemoteURL
  alias TuistWeb.API.Responses
  alias TuistWeb.API.Schemas.CargoBuild
  alias TuistWeb.API.Schemas.Error
  alias TuistWeb.Authentication

  plug TuistWeb.Plugs.CastAndValidate, json_render_error_v2: true, render_error: TuistWeb.RenderAPIErrorPlug
  plug TuistWeb.Plugs.LoaderPlug
  plug TuistWeb.API.Authorization.AuthorizationPlug, :build

  tags ["Cargo"]

  @duration %Schema{type: :integer, minimum: 0, maximum: 4_294_967_295}
  @string %Schema{type: :string, maxLength: 4096}
  @properties Map.merge(
                Map.new(
                  ~w(command rust_version contract_version git_branch git_commit_sha git_ref git_remote_url_origin ci_provider ci_run_id ci_project_handle ci_host)a,
                  &{&1, @string}
                ),
                %{
                  id: %Schema{type: :string, format: :uuid},
                  duration_ms: @duration,
                  status: %Schema{type: :string, enum: ["success", "failure"]},
                  is_ci: %Schema{type: :boolean},
                  started_at: %Schema{type: :string, format: :"date-time"},
                  custom_metadata: %Schema{
                    type: :object,
                    properties: %{
                      tags: %Schema{type: :array, maxItems: 50, items: %Schema{type: :string, maxLength: 50}},
                      values: %Schema{
                        type: :object,
                        maxProperties: 64,
                        additionalProperties: %Schema{type: :string, maxLength: 500}
                      }
                    }
                  },
                  cache: %Schema{
                    type: :object,
                    additionalProperties: false,
                    properties:
                      CacheMetrics.counters()
                      |> Map.new(&{&1, %Schema{type: :integer, minimum: 0, maximum: CacheMetrics.maximum()}})
                      |> Map.put(:version, %Schema{type: :integer, enum: [1]})
                      |> Map.put(:details, CacheDetails.schema()),
                    required: [:version]
                  },
                  compilations: %Schema{
                    type: :array,
                    maxItems: 20_000,
                    items: %Schema{
                      type: :object,
                      properties: %{
                        name: @string,
                        source: @string,
                        kind: @string,
                        dependencies: %Schema{
                          type: :array,
                          maxItems: 5000,
                          items: %Schema{type: :string, maxLength: 1024}
                        },
                        start_offset_ms: @duration,
                        duration_ms: @duration,
                        status: %Schema{type: :string, enum: ["success", "failure"]},
                        diagnostics: %Schema{
                          type: :array,
                          maxItems: 100,
                          items: %Schema{
                            type: :object,
                            properties: %{
                              severity: %Schema{type: :string, enum: ["warning", "error"]},
                              message: %Schema{type: :string, maxLength: 10_000},
                              file: @string,
                              line: %Schema{type: :integer, minimum: 0, maximum: 4_294_967_295}
                            },
                            required: [:severity, :message]
                          }
                        }
                      },
                      required: [:name, :source, :kind, :dependencies, :start_offset_ms, :duration_ms, :status]
                    }
                  }
                }
              )

  operation :create_build,
    summary: "Record a Cargo invocation and its observed rustc compilations.",
    operation_id: "createCargoBuild",
    parameters: [
      account_handle: [in: :path, type: :string, required: true],
      project_handle: [in: :path, type: :string, required: true]
    ],
    request_body:
      {"Cargo build", "application/json",
       %Schema{type: :object, properties: @properties, required: [:id, :duration_ms, :status]}},
    responses: %{
      created:
        {"Build created", "application/json",
         %Schema{type: :object, properties: %{id: %Schema{type: :string, format: :uuid}}, required: [:id]}},
      bad_request: {"Invalid report", "application/json", Error},
      forbidden: {"Access denied", "application/json", Error},
      too_many_requests: Responses.authorization_throttled()
    }

  def create_build(%{assigns: %{selected_project: project}, body_params: body} = conn, _params) do
    attrs =
      body
      |> RemoteURL.strip_credentials_from_params()
      |> Map.merge(%{project_id: project.id, account_id: Authentication.authenticated_subject_account(conn).id})

    case Cargo.create_build(attrs) do
      {:ok, id} ->
        Projects.notify_connected(project, Authentication.current_user(conn))
        conn |> put_status(:created) |> json(%{id: id})

      {:error, _} ->
        conn |> put_status(:bad_request) |> json(%{message: "Invalid Cargo build report."})
    end
  end

  operation :list_builds,
    summary: "List Cargo builds for a project, newest first.",
    description: "Cargo test runs reported as nextest are listed with test runs, not builds.",
    operation_id: "listCargoBuilds",
    parameters: [
      account_handle: [in: :path, type: :string, required: true, description: "The handle of the account."],
      project_handle: [in: :path, type: :string, required: true, description: "The handle of the project."],
      git_branch: [in: :query, type: :string, description: "Filter by git branch."],
      status: [
        in: :query,
        type: %Schema{title: "CargoBuildStatus", type: :string, enum: ["success", "failure"]},
        description: "Filter by build status."
      ],
      is_ci: [in: :query, type: :boolean, description: "Filter by whether the build ran on CI."],
      command: [in: :query, type: :string, description: "Filter by Cargo subcommand, for example build or check."],
      page_size: [
        in: :query,
        type: %Schema{
          title: "CargoBuildsIndexPageSize",
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
          title: "CargoBuildsIndexPage",
          description: "The page number to return.",
          type: :integer,
          default: 1,
          minimum: 1
        }
      ]
    ],
    responses: %{
      ok: {"List of Cargo builds", "application/json", CargoBuild.list()},
      forbidden: {"You don't have permission to access this resource", "application/json", Error},
      too_many_requests: Responses.authorization_throttled()
    }

  def list_builds(%{assigns: %{selected_project: project}, params: params} = conn, _params) do
    json(conn, Query.list_builds(project.id, string_keys(params)))
  end

  operation :get_build,
    summary: "Get a Cargo build with its decoded cache counters.",
    operation_id: "getCargoBuild",
    parameters: [
      account_handle: [in: :path, type: :string, required: true, description: "The handle of the account."],
      project_handle: [in: :path, type: :string, required: true, description: "The handle of the project."],
      build_id: [in: :path, type: :string, required: true, description: "The build ID."]
    ],
    responses: %{
      ok: {"Cargo build details", "application/json", CargoBuild.detail()},
      not_found: {"Build not found", "application/json", Error},
      forbidden: {"You don't have permission to access this resource", "application/json", Error},
      too_many_requests: Responses.authorization_throttled()
    }

  def get_build(%{assigns: %{selected_project: project}, params: %{build_id: build_id}} = conn, _params) do
    case Query.get_build(project.id, build_id) do
      {:ok, build} -> json(conn, build)
      {:error, :not_found} -> conn |> put_status(:not_found) |> json(%{message: "Build not found."})
    end
  end

  defp string_keys(params), do: Map.new(params, fn {key, value} -> {to_string(key), value} end)
end
