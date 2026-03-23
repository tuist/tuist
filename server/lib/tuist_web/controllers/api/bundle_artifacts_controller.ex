defmodule TuistWeb.API.BundleArtifactsController do
  use OpenApiSpex.ControllerSpecs
  use TuistWeb, :controller

  alias OpenApiSpex.Schema
  alias Tuist.Bundles
  alias TuistWeb.API.Schemas.Error

  plug(TuistWeb.Plugs.InstrumentedCastAndValidate,
    json_render_error_v2: true,
    render_error: TuistWeb.RenderAPIErrorPlug
  )

  plug(TuistWeb.Plugs.LoaderPlug)
  plug(TuistWeb.API.Authorization.AuthorizationPlug, :bundle)

  tags ["Bundles"]

  operation(:show,
    summary: "Get the artifact tree for a bundle.",
    operation_id: "getBundleArtifactTree",
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
      bundle_id: [
        in: :path,
        schema: %Schema{type: :string, format: :uuid},
        required: true,
        description: "The ID of the bundle."
      ]
    ],
    responses: %{
      ok:
        {"Bundle artifact tree", "application/json",
         %Schema{
           type: :object,
           properties: %{
             bundle_id: %Schema{type: :string, format: :uuid, description: "The bundle ID."},
             artifacts: %Schema{
               type: :array,
               items: %Schema{
                 type: :object,
                 properties: %{
                   artifact_type: %Schema{type: :string, description: "The type of the artifact."},
                   path: %Schema{type: :string, description: "The artifact path."},
                   size: %Schema{type: :integer, description: "The artifact size in bytes."}
                 },
                 required: [:artifact_type, :path, :size]
               }
             }
           },
           required: [:bundle_id, :artifacts]
         }},
      not_found: {"Bundle not found", "application/json", Error},
      forbidden: {"You don't have permission to access this resource", "application/json", Error}
    }
  )

  def show(%{assigns: %{selected_project: selected_project}, params: %{bundle_id: bundle_id}} = conn, _params) do
    case Bundles.get_bundle(bundle_id) do
      {:ok, %{project_id: project_id}} when project_id == selected_project.id ->
        artifacts = Bundles.get_bundle_artifact_tree(bundle_id)

        json(conn, %{
          bundle_id: bundle_id,
          artifacts:
            Enum.map(artifacts, fn artifact ->
              %{
                artifact_type: artifact.artifact_type,
                path: artifact.path,
                size: artifact.size
              }
            end)
        })

      _error ->
        conn
        |> put_status(:not_found)
        |> json(%{message: "Bundle not found."})
    end
  end
end
