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
  alias TuistWeb.API.Schemas.ValidationError
  alias TuistWeb.Authentication

  plug(TuistWeb.Plugs.LoaderPlug)
  plug(TuistWeb.API.Authorization.AuthorizationPlug, :bundle)

  tags ["Bundles"]

  operation :index,
    summary: "List bundles for a project",
    operation_id: "listBundles",
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
      ],
      git_branch: [
        in: :query,
        type: :string,
        description: "Filter bundles by git branch."
      ],
      page: [
        in: :query,
        type: :integer,
        description: "Page number for pagination (starting from 1)."
      ],
      page_size: [
        in: :query,
        type: :integer,
        description: "Number of items per page (max 100)."
      ]
    },
    responses: %{
      ok: {"List of bundles", "application/json", %Schema{
        type: :object,
        properties: %{
          bundles: %Schema{
            type: :array,
            items: TuistWeb.API.Schemas.Bundle
          },
          meta: %Schema{
            type: :object,
            properties: %{
              total_count: %Schema{type: :integer},
              page_size: %Schema{type: :integer},
              has_next_page: %Schema{type: :boolean},
              has_previous_page: %Schema{type: :boolean}
            }
          }
        }
      }},
      unauthorized: {"You need to be authenticated to list bundles", "application/json", Error},
      forbidden: {"You are not authorized to list bundles", "application/json", Error}
    }

  operation :show,
    summary: "Get a specific bundle",
    operation_id: "getBundle",
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
      ],
      bundle_id: [
        in: :path,
        type: :string,
        required: true,
        description: "The ID of the bundle."
      ]
    },
    responses: %{
      ok: {"Bundle details", "application/json", TuistWeb.API.Schemas.Bundle},
      not_found: {"Bundle not found", "application/json", Error},
      unauthorized: {"You need to be authenticated to get a bundle", "application/json", Error},
      forbidden: {"You are not authorized to get a bundle", "application/json", Error}
    }

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

  def index(%{assigns: %{selected_project: selected_project}} = conn, params) do
    filter_params = %{
      "filters" => [
        %{
          "field" => "project_id",
          "op" => :==,
          "value" => selected_project.id
        }
      ],
      "order_by" => ["inserted_at"],
      "order_directions" => [:desc]
    }

    filter_params =
      if params["git_branch"] do
        Map.put(filter_params, "filters", [
          %{
            "field" => "git_branch",
            "op" => :==,
            "value" => params["git_branch"]
          } | filter_params["filters"]
        ])
      else
        filter_params
      end

    filter_params =
      if params["page"] do
        Map.put(filter_params, "page", String.to_integer(params["page"]))
      else
        filter_params
      end

    filter_params =
      if params["page_size"] do
        page_size = min(String.to_integer(params["page_size"]), 100)
        Map.put(filter_params, "page_size", page_size)
      else
        filter_params
      end

    case Bundles.list_bundles(filter_params, preload: [:project, :uploaded_by_account]) do
      {bundles, meta} ->
        formatted_bundles = Enum.map(bundles, &format_bundle/1)
        
        json(conn, %{
          bundles: formatted_bundles,
          meta: %{
            total_count: meta.total_count,
            page_size: meta.page_size,
            has_next_page: meta.has_next_page?,
            has_previous_page: meta.has_previous_page?
          }
        })

      {:error, changeset} ->
        conn
        |> put_status(:bad_request)
        |> json(%{message: "Invalid filter parameters", errors: changeset.errors})
    end
  end

  def show(%{assigns: %{selected_project: selected_project}} = conn, %{"bundle_id" => bundle_id}) do
    case Bundles.get_bundle(bundle_id, preload: [:project, :uploaded_by_account]) do
      {:ok, bundle} ->
        if bundle.project_id == selected_project.id do
          json(conn, format_bundle(bundle))
        else
          conn
          |> put_status(:not_found)
          |> json(%{message: "Bundle not found"})
        end

      {:error, :not_found} ->
        conn
        |> put_status(:not_found)
        |> json(%{message: "Bundle not found"})
    end
  end

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

  defp format_bundle(bundle) do
    %{
      id: bundle.id,
      app_bundle_id: bundle.app_bundle_id,
      name: bundle.name,
      install_size: bundle.install_size,
      download_size: bundle.download_size,
      supported_platforms: bundle.supported_platforms,
      version: bundle.version,
      git_branch: bundle.git_branch,
      git_commit_sha: bundle.git_commit_sha,
      git_ref: bundle.git_ref,
      inserted_at: bundle.inserted_at,
      updated_at: bundle.updated_at,
      artifacts: if Ecto.assoc_loaded?(bundle.artifacts) do
        bundle.artifacts
      else
        []
      end
    }
  end
end
