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
  alias TuistWeb.API.Schemas.Bundle
  alias TuistWeb.API.Schemas.BundleArtifact
  alias TuistWeb.API.Schemas.Error
  alias TuistWeb.API.Schemas.ValidationError
  alias TuistWeb.Authentication

  plug(TuistWeb.Plugs.LoaderPlug)
  plug(TuistWeb.API.Authorization.AuthorizationPlug, :bundle)

  plug(
    OpenApiSpex.Plug.CastAndValidate,
    json_render_error_v2: true,
    render_error: TuistWeb.RenderAPIErrorPlug
  )

  tags(["Bundles"])

  operation(:index,
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
        required: false,
        description: "Filter bundles by git branch."
      ],
      page: [
        in: :query,
        type: :integer,
        required: false,
        description: "Page number for pagination."
      ],
      page_size: [
        in: :query,
        type: :integer,
        required: false,
        description: "Number of items per page."
      ]
    },
    responses: %{
      ok:
        {"List of bundles", "application/json",
         %Schema{
           type: :object,
           properties: %{
             bundles: %Schema{
               type: :array,
               items: Bundle
             },
             meta: TuistWeb.API.Schemas.PaginationMetadata
           },
           required: [:bundles, :meta]
         }},
      unauthorized: {"You need to be authenticated to list bundles", "application/json", Error},
      forbidden: {"You are not authorized to list bundles", "application/json", Error}
    }
  )

  def index(%{assigns: %{selected_project: selected_project}} = conn, params) do
    filters = [
      %{field: :project_id, op: :==, value: selected_project.id}
    ]

    filters =
      case Map.get(params, :git_branch) do
        nil -> filters
        branch -> [%{field: :git_branch, op: :==, value: branch} | filters]
      end

    flop_params = %{
      filters: filters,
      order_by: [:inserted_at],
      order_directions: [:desc],
      page_size: Map.get(params, :page_size, 20)
    }

    flop_params =
      case Map.get(params, :page) do
        nil -> flop_params
        page -> Map.put(flop_params, :page, page)
      end

    {bundles, meta} =
      Bundles.list_bundles(flop_params, preload: [:uploaded_by_account, project: :account])

    conn
    |> put_status(:ok)
    |> json(%{
      bundles: Enum.map(bundles, &bundle_list_to_map/1),
      meta: %{
        has_next_page: meta.has_next_page?,
        has_previous_page: meta.has_previous_page?,
        current_page: meta.current_page,
        page_size: meta.page_size,
        total_count: meta.total_count,
        total_pages: meta.total_pages
      }
    })
  end

  operation(:show,
    summary: "Get a single bundle by ID",
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
        schema: %Schema{type: :string, format: :uuid},
        required: true,
        description: "The ID of the bundle."
      ]
    },
    responses: %{
      ok: {"Bundle details", "application/json", Bundle},
      unprocessable_entity: {"Invalid request parameters", "application/json", Error},
      not_found: {"Bundle not found", "application/json", Error},
      unauthorized: {"You need to be authenticated to view this bundle", "application/json", Error},
      forbidden: {"You are not authorized to view this bundle", "application/json", Error}
    }
  )

  def show(%{assigns: %{selected_project: selected_project}} = conn, params) do
    bundle_id = params[:bundle_id]

    case Bundles.get_bundle(bundle_id,
           project_id: selected_project.id,
           preload: [:uploaded_by_account, project: :account]
         ) do
      {:ok, bundle} ->
        conn
        |> put_status(:ok)
        |> json(bundle_to_map(bundle))

      {:error, :not_found} ->
        conn
        |> put_status(:not_found)
        |> json(%{message: "Bundle not found"})
    end
  end

  operation(:create,
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
               type: %Schema{
                 type: :string,
                 enum: ["ipa", "app", "xcarchive"],
                 description: "The type of the bundle"
               },
               artifacts: %Schema{
                 type: :array,
                 description: "The artifacts in this bundle",
                 items: BundleArtifact
               }
             },
             required: [
               :app_bundle_id,
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
      ok: {"The bundle was created successfully", "application/json", Bundle},
      bad_request: {"Validation errors occurred", "application/json", ValidationError},
      unauthorized: {"You need to be authenticated to create a bundle", "application/json", Error},
      forbidden: {"You are not authorized to create a bundle", "application/json", Error}
    }
  )

  def create(%{assigns: %{selected_project: selected_project}, body_params: body_params} = conn, _params) do
    bundle_params = body_params[:bundle]
    id = UUIDv7.generate()

    account_id =
      case Authentication.authenticated_subject(conn) do
        %Project{} = project -> project.account.id
        %User{} = user -> user.account.id
        %AuthenticatedAccount{account: account} -> account.id
      end

    # Derive type if not provided for older CLI versions: :ipa if download_size is specified, :app otherwise
    type =
      Map.get(bundle_params, :type) ||
        derive_bundle_type(Map.get(bundle_params, :download_size))

    # Convert OpenApiSpex BundleArtifact structs to plain maps with atom keys
    artifacts =
      bundle_params
      |> Map.get(:artifacts, [])
      |> Enum.map(&struct_to_map/1)

    with {:ok, %Bundles.Bundle{} = bundle} <-
           Bundles.create_bundle(
             %{
               id: id,
               project_id: selected_project.id,
               app_bundle_id: Map.get(bundle_params, :app_bundle_id),
               name: Map.get(bundle_params, :name),
               install_size: Map.get(bundle_params, :install_size),
               download_size: Map.get(bundle_params, :download_size),
               supported_platforms: Map.get(bundle_params, :supported_platforms),
               version: Map.get(bundle_params, :version),
               artifacts: artifacts,
               git_branch: Map.get(bundle_params, :git_branch),
               git_commit_sha: Map.get(bundle_params, :git_commit_sha),
               git_ref: Map.get(bundle_params, :git_ref),
               type: type,
               uploaded_by_account_id: account_id
             },
             preload: [:uploaded_by_account, project: [:account]]
           ) do
      conn
      |> put_status(:ok)
      |> json(bundle_to_map(bundle))
    end
  end

  # Convert OpenApiSpex structs to plain maps with atom keys, recursively
  defp struct_to_map(%BundleArtifact{} = artifact) do
    %{
      artifact_type: artifact.artifact_type,
      path: artifact.path,
      size: artifact.size,
      shasum: artifact.shasum,
      children: artifact.children && Enum.map(artifact.children, &struct_to_map/1)
    }
  end

  defp derive_bundle_type(download_size) when is_nil(download_size), do: "app"
  defp derive_bundle_type(_download_size), do: "ipa"

  defp bundle_list_to_map(bundle) do
    %{
      id: bundle.id,
      name: bundle.name,
      app_bundle_id: bundle.app_bundle_id,
      version: bundle.version,
      supported_platforms: bundle.supported_platforms,
      install_size: bundle.install_size,
      download_size: bundle.download_size,
      git_branch: bundle.git_branch,
      git_commit_sha: bundle.git_commit_sha,
      git_ref: bundle.git_ref,
      type: bundle.type,
      inserted_at: bundle.inserted_at,
      uploaded_by_account: bundle.uploaded_by_account.name,
      url: url(~p"/#{bundle.project.account.name}/#{bundle.project.name}/bundles/#{bundle.id}")
    }
  end

  defp bundle_to_map(bundle) do
    artifacts =
      case bundle.artifacts do
        %Ecto.Association.NotLoaded{} -> []
        artifacts -> Enum.map(artifacts, &artifact_to_map/1)
      end

    %{
      id: bundle.id,
      name: bundle.name,
      app_bundle_id: bundle.app_bundle_id,
      version: bundle.version,
      supported_platforms: bundle.supported_platforms,
      install_size: bundle.install_size,
      download_size: bundle.download_size,
      git_branch: bundle.git_branch,
      git_commit_sha: bundle.git_commit_sha,
      git_ref: bundle.git_ref,
      type: bundle.type,
      inserted_at: bundle.inserted_at,
      uploaded_by_account: bundle.uploaded_by_account.name,
      artifacts: artifacts,
      url: url(~p"/#{bundle.project.account.name}/#{bundle.project.name}/bundles/#{bundle.id}")
    }
  end

  defp artifact_to_map(artifact) do
    %{
      artifact_type: artifact.artifact_type,
      path: artifact.path,
      size: artifact.size,
      shasum: artifact.shasum,
      children:
        if(artifact.children && !Enum.empty?(artifact.children),
          do: Enum.map(artifact.children, &artifact_to_map/1)
        )
    }
  end
end
