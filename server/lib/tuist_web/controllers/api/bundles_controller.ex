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
  alias TuistWeb.API.Schemas.Error
  alias TuistWeb.API.Schemas.ValidationError
  alias TuistWeb.Authentication

  plug(TuistWeb.Plugs.LoaderPlug)
  plug(TuistWeb.API.Authorization.AuthorizationPlug, :bundle)

  tags ["Bundles"]

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
               git_ref: %Schema{
                 type: :string,
                 description:
                   "Git reference of the repository. When run from CI in a pull request, this will be the remote reference to the pull request, such as `refs/pull/23958/merge`."
               },
               artifacts: %Schema{
                 type: :array,
                 description: "The artifacts in this bundle",
                 items: BundleArtifact
               }
             },
             required: [
               :bundle_id,
               :name,
               :supported_platforms,
               :version,
               :install_size,
               :artifacts
             ]
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
      ok: {"The bundle was created successfully", "application/json", TuistWeb.API.Schemas.Bundle},
      bad_request: {"Validation errors occurred", "application/json", ValidationError},
      unauthorized: {"You need to be authenticated to create a bundle", "application/json", Error},
      forbidden: {"You are not authorized to create a bundle", "application/json", Error}
    }

  def create(%{assigns: %{selected_project: selected_project}} = conn, params) do
    bundle = params["bundle"]
    id = UUIDv7.generate()

    account_id =
      case Authentication.authenticated_subject(conn) do
        %Project{} = project -> project.account.id
        %User{} = user -> user.account.id
        %AuthenticatedAccount{account: account} -> account.id
      end

    with {:ok, %Bundle{} = bundle} <-
           Bundles.create_bundle(%{
             id: id,
             project_id: selected_project.id,
             app_bundle_id: bundle["app_bundle_id"],
             name: bundle["name"],
             install_size: bundle["install_size"],
             download_size: bundle["download_size"],
             supported_platforms: bundle["supported_platforms"],
             version: bundle["version"],
             artifacts: bundle["artifacts"],
             git_branch: bundle["git_branch"],
             git_commit_sha: bundle["git_commit_sha"],
             git_ref: bundle["git_ref"],
             uploaded_by_account_id: account_id
           }) do
      conn
      |> put_status(:ok)
      |> json(%{
        id: bundle.id,
        url: url(~p"/#{selected_project.account.name}/#{selected_project.name}/bundles/#{bundle.id}")
      })
    end
  end
end
