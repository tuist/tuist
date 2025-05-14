alias TuistWeb.API.Schemas.BundleSupportedPlatform

defmodule TuistWeb.API.BundlesController do
  use TuistWeb, :controller
  use OpenApiSpex.ControllerSpecs

  alias OpenApiSpex.Schema
  alias Tuist.Accounts.AuthenticatedAccount
  alias Tuist.Accounts.User
  alias Tuist.Bundles
  alias Tuist.Bundles.Bundle
  alias Tuist.Projects.Project
  alias TuistWeb.API.Schemas.BundleArtifact
  alias TuistWeb.API.Schemas.BundleSupportedPlatform
  alias TuistWeb.API.Schemas.Error
  alias TuistWeb.Authentication

  plug(TuistWeb.Plugs.LoaderPlug)
  plug(TuistWeb.API.Authorization.AuthorizationPlug, :bundle)

  operation :create,
    summary: "Create a new bundle with artifacts",
    operation_id: "createBundle",
    request_body:
      {"Bundle params", "application/json",
       %Schema{
         title: "BundleRequest",
         description: "Request schema for bundle creation",
         type: :object,
         properties: %{
           bundle: %Schema{
             type: :object,
             properties: %{
               app_bundle_id: %Schema{
                 type: :string,
                 description: "The bundle ID of the app"
               },
               name: %Schema{
                 type: :string,
                 description: "The name of the bundle"
               },
               supported_platforms: %Schema{
                 type: :array,
                 description: "List of supported platforms",
                 items: BundleSupportedPlatform
               },
               version: %Schema{
                 type: :string,
                 description: "The version of the bundle"
               },
               install_size: %Schema{
                 type: :integer,
                 description: "The bundle install size in bytes"
               },
               download_size: %Schema{
                 type: :integer,
                 description: "The bundle download size in bytes"
               },
               git_branch: %Schema{
                 type: :string,
                 description: "The git branch associated with the bundle."
               },
               git_commit_sha: %Schema{
                 type: :string,
                 description: "The git commit SHA associated with the bundle."
               },
               artifacts: %Schema{
                 type: :array,
                 description: "The artifacts in this bundle",
                 items: BundleArtifact
               }
             },
             required: [:bundle_id, :name, :supported_platforms, :version, :install_size, :artifacts]
           }
         },
         required: [:bundle]
       }},
    parameters: %{
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
      ]
    },
    responses: %{
      ok: {"The bundle was created", "application/json", TuistWeb.API.Schemas.Bundle},
      bad_request: {"An error occurred while updating the account.", "application/json", Error},
      unauthorized: {"You need to be authenticated to update your account.", "application/json", Error}
    }

  def create(%{assigns: %{selected_project: selected_project}, body_params: body_params} = conn, params) do
    bundle = params["bundle"]
    id = UUIDv7.generate()

    account_id =
      case Authentication.authenticated_subject(conn) do
        %Project{} = project -> project.account.id
        %User{} = user -> user.account.id
        %AuthenticatedAccount{account: account} -> account.id
      end

    case Bundles.create_bundle(%{
           id: id,
           project_id: selected_project.id,
           app_bundle_id: bundle["app_bundle_id"],
           name: bundle["name"],
           install_size: bundle["install_size"],
           download_size: bundle["download_size"],
           supported_platforms: bundle["supported_platforms"],
           version: bundle["version"],
           artifacts: Enum.map(bundle["artifacts"], &map_artifact(&1, id)),
           git_branch: bundle["git_branch"],
           git_commit_sha: bundle["git_commit_sha"],
           uploaded_by_account_id: account_id
         }) do
      {:ok, %Bundle{} = bundle} ->
        conn
        |> put_status(:ok)
        |> json(%{
          id: bundle.id,
          url: url(~p"/#{selected_project.account.name}/#{selected_project.name}/bundles/#{bundle.id}")
        })

      {:error, %Ecto.Changeset{} = changeset} ->
        message =
          changeset
          |> Ecto.Changeset.traverse_errors(fn {message, _opts} -> message end)
          |> Enum.map_join(", ", fn {key, value} -> "#{Atom.to_string(key)} field #{value}" end)

        conn |> put_status(:bad_request) |> json(%Error{message: message})
    end
  end

  defp map_artifact(artifact, bundle_id) do
    artifact = Map.put(artifact, "bundle_id", bundle_id)

    if is_nil(artifact["children"]) do
      artifact
    else
      Map.put(artifact, "children", Enum.map(artifact["children"], &map_artifact(&1, bundle_id)))
    end
  end
end
