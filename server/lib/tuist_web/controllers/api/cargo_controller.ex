defmodule TuistWeb.API.CargoController do
  use OpenApiSpex.ControllerSpecs
  use TuistWeb, :controller

  alias OpenApiSpex.Schema
  alias Tuist.Cargo
  alias Tuist.Cargo.CacheDetails
  alias Tuist.Cargo.CacheMetrics
  alias Tuist.Projects
  alias Tuist.VCS.RemoteURL
  alias TuistWeb.API.Responses
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
end
