defmodule TuistWeb.API.PreviewsController do
  use OpenApiSpex.ControllerSpecs
  use TuistWeb, :controller

  alias OpenApiSpex.Schema
  alias Tuist.Accounts.AuthenticatedAccount
  alias Tuist.Accounts.User
  alias Tuist.AppBuilds
  alias Tuist.Projects.Project
  alias Tuist.QA
  alias Tuist.Storage
  alias TuistWeb.API.Schemas
  alias TuistWeb.API.Schemas.ArtifactMultipartUploadPart
  alias TuistWeb.API.Schemas.ArtifactMultipartUploadParts
  alias TuistWeb.API.Schemas.ArtifactMultipartUploadUrl
  alias TuistWeb.API.Schemas.ArtifactUploadURL
  alias TuistWeb.API.Schemas.Error
  alias TuistWeb.API.Schemas.PaginationMetadata
  alias TuistWeb.API.Schemas.PreviewSupportedPlatform
  alias TuistWeb.Authentication

  plug(TuistWeb.Plugs.API.TransformQueryArrayParamsPlug, [:supported_platforms])

  plug(OpenApiSpex.Plug.CastAndValidate,
    json_render_error_v2: true,
    render_error: TuistWeb.RenderAPIErrorPlug
  )

  plug(TuistWeb.Plugs.LoaderPlug)
  plug(TuistWeb.API.Authorization.AuthorizationPlug, :preview)

  tags(["Previews"])

  operation(:multipart_start,
    summary: "It initiates a multipart upload for a preview artifact.",
    description:
      "The endpoint returns an upload ID that can be used to generate URLs for the individual parts and complete the upload.",
    operation_id: "startPreviewsMultipartUpload",
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
      ]
    ],
    request_body:
      {"Preview upload request params", "application/json",
       %Schema{
         type: :object,
         properties: %{
           display_name: %Schema{type: :string, description: "The display name of the preview."},
           type: %Schema{
             enum: ["app_bundle", "ipa"],
             type: :string,
             description: "The type of the preview to upload.",
             default: "app_bundle"
           },
           bundle_identifier: %Schema{
             type: :string,
             description: "The bundle identifier of the preview."
           },
           version: %Schema{
             type: :string,
             description: "The version of the preview."
           },
           supported_platforms: %Schema{
             type: :array,
             items: PreviewSupportedPlatform,
             description: "The supported platforms of the preview."
           },
           git_branch: %Schema{
             type: :string,
             description: "The git branch associated with the preview."
           },
           git_commit_sha: %Schema{
             type: :string,
             description: "The git commit SHA associated with the preview."
           },
           git_ref: %Schema{
             type: :string,
             description: "The git ref associated with the preview."
           },
           binary_id: %Schema{
             type: :string,
             description: "The Mach-O UUID of the binary"
           },
           track: %Schema{
             type: :string,
             description: "The track for the preview (e.g., 'beta', 'nightly')."
           },
           build_version: %Schema{
             type: :string,
             description: "The CFBundleVersion of the app."
           }
         }
       }},
    responses: %{
      ok:
        {"The upload has been started", "application/json",
         %Schema{
           title: "PreviewArtifactUpload",
           description:
             "The upload has been initiated and preview and upload unique identifier are returned to upload the various parts using multi-part uploads",
           type: :object,
           properties: %{
             status: %Schema{type: :string, default: "success", enum: ["success"]},
             data: %Schema{
               type: :object,
               description:
                 "Data that contains preview and upload unique identifier associated with the multipart upload to use when uploading parts",
               properties: %{
                 upload_id: %Schema{type: :string, description: "The upload ID"},
                 preview_id: %Schema{
                   type: :string,
                   description: "The id of the preview.",
                   deprecated: true
                 },
                 app_build_id: %Schema{type: :string, description: "The id of the app build."}
               },
               required: [:upload_id, :app_build_id]
             }
           },
           required: [:status, :data]
         }},
      conflict: {"An app build with the same binary ID and build version already exists", "application/json", Error},
      unauthorized: {"You need to be authenticated to access this resource", "application/json", Error},
      forbidden: {"The authenticated subject is not authorized to perform this action", "application/json", Error},
      not_found: {"The project doesn't exist", "application/json", Error}
    }
  )

  def multipart_start(
        %{
          path_params: %{"account_handle" => account_handle, "project_handle" => project_handle},
          body_params: body_params,
          assigns: %{selected_project: selected_project}
        } = conn,
        _params
      ) do
    account =
      case Authentication.authenticated_subject(conn) do
        %Project{} = project -> project.account
        %User{} = user -> user.account
        %AuthenticatedAccount{account: account} -> account
      end

    supported_platforms = Map.get(body_params, :supported_platforms, [])
    type = body_params |> Map.get(:type) |> String.to_atom()

    {:ok, preview} =
      AppBuilds.find_or_create_preview(%{
        project_id: selected_project.id,
        bundle_identifier: Map.get(body_params, :bundle_identifier),
        version: Map.get(body_params, :version),
        git_commit_sha: Map.get(body_params, :git_commit_sha),
        created_by_account_id: account.id,
        display_name: Map.get(body_params, :display_name),
        git_branch: Map.get(body_params, :git_branch),
        git_ref: Map.get(body_params, :git_ref),
        supported_platforms: [],
        track: Map.get(body_params, :track)
      })

    binary_id = Map.get(body_params, :binary_id)
    build_version = Map.get(body_params, :build_version)

    case AppBuilds.create_app_build(%{
           preview_id: preview.id,
           project_id: selected_project.id,
           type: type,
           display_name: Map.get(body_params, :display_name),
           bundle_identifier: Map.get(body_params, :bundle_identifier),
           version: Map.get(body_params, :version),
           git_branch: Map.get(body_params, :git_branch),
           git_commit_sha: Map.get(body_params, :git_commit_sha),
           created_by_account_id: account.id,
           supported_platforms: supported_platforms,
           binary_id: binary_id,
           build_version: build_version
         }) do
      {:ok, app_build} ->
        upload_id =
          Storage.multipart_start(
            AppBuilds.storage_key(%{
              account_handle: account_handle,
              project_handle: project_handle,
              app_build_id: app_build.id
            }),
            selected_project.account
          )

        # We're returning app_build.id as preview_id, so we don't break CLI pre-4.54.0 version.
        json(conn, %{
          status: "success",
          data: %{upload_id: upload_id, preview_id: app_build.id, app_build_id: app_build.id}
        })

      {:error, %Ecto.Changeset{errors: errors}} ->
        if Keyword.has_key?(errors, :binary_id) do
          conn
          |> put_status(:conflict)
          |> json(%{
            status: "error",
            code: "duplicate_app_build",
            message:
              "An app build with the same binary ID '#{binary_id}' and build version '#{build_version}' already exists."
          })
        else
          raise "Unexpected error creating app build: #{inspect(errors)}"
        end
    end
  end

  operation(:multipart_generate_url,
    summary: "It generates a signed URL for uploading a part.",
    description:
      "Given an upload ID and a part number, this endpoint returns a signed URL that can be used to upload a part of a multipart upload. The URL is short-lived and expires in 120 seconds.",
    operation_id: "generatePreviewsMultipartUploadURL",
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
      ]
    ],
    request_body:
      {"Artifact to generate a signed URL for", "application/json",
       %Schema{
         type: :object,
         properties: %{
           multipart_upload_part: ArtifactMultipartUploadPart,
           preview_id: %Schema{
             type: :string,
             description: "The id of the preview.",
             deprecated: true
           },
           app_build_id: %Schema{
             type: :string,
             description: "The id of the app build."
           }
         },
         required: [:multipart_upload_part, :preview_id]
       }},
    responses: %{
      ok: {"The URL has been generated", "application/json", ArtifactMultipartUploadUrl},
      unauthorized: {"You need to be authenticated to access this resource", "application/json", Error},
      forbidden: {"The authenticated subject is not authorized to perform this action", "application/json", Error},
      not_found: {"The project doesn't exist", "application/json", Error}
    }
  )

  def multipart_generate_url(
        %{
          assigns: %{selected_project: selected_project},
          path_params: %{"account_handle" => account_handle, "project_handle" => project_handle},
          body_params:
            %{
              preview_id: preview_id,
              multipart_upload_part: %{part_number: part_number, upload_id: upload_id} = multipart_upload_part
            } = body_params
        } = conn,
        _params
      ) do
    # The preview_id is still used to support CLI version pre 4.54.0
    app_build_id = Map.get(body_params, :app_build_id, preview_id)
    expires_in = 120
    content_length = Map.get(multipart_upload_part, :content_length)

    object_key =
      AppBuilds.storage_key(%{
        account_handle: account_handle,
        project_handle: project_handle,
        app_build_id: app_build_id
      })

    url =
      Storage.multipart_generate_url(
        object_key,
        upload_id,
        part_number,
        selected_project.account,
        expires_in: expires_in,
        content_length: content_length
      )

    json(conn, %{status: "success", data: %{url: url}})
  end

  operation(:multipart_complete,
    summary: "It completes a multi-part upload.",
    description: "Given the upload ID and all the parts with their ETags, this endpoint completes the multipart upload.",
    operation_id: "completePreviewsMultipartUpload",
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
      ]
    ],
    request_body:
      {"preview multipart upload completion", "application/json",
       %Schema{
         description: "The request body to complete the multipart upload of a preview.",
         type: :object,
         properties: %{
           multipart_upload_parts: ArtifactMultipartUploadParts,
           preview_id: %Schema{
             type: :string,
             description: "The id of the preview.",
             deprecated: true
           },
           app_build_id: %Schema{
             type: :string,
             description: "The id of the app build."
           }
         },
         required: [:multipart_upload_parts, :preview_id]
       }},
    responses: %{
      ok: {"The upload has been completed", "application/json", TuistWeb.API.Schemas.Preview},
      unauthorized: {"You need to be authenticated to access this resource", "application/json", Error},
      forbidden: {"The authenticated subject is not authorized to perform this action", "application/json", Error},
      not_found: {"The project or preview doesn't exist", "application/json", Error}
    }
  )

  def multipart_complete(
        %{
          assigns: %{selected_project: selected_project},
          path_params: %{"account_handle" => account_handle, "project_handle" => project_handle},
          body_params:
            %{
              preview_id: preview_id,
              multipart_upload_parts: %ArtifactMultipartUploadParts{parts: parts, upload_id: upload_id}
            } = body_params
        } = conn,
        _params
      ) do
    # The preview_id is still used to support CLI version pre 4.54.0
    app_build_id = Map.get(body_params, :app_build_id, preview_id)

    case AppBuilds.app_build_by_id(app_build_id, preload: [:preview]) do
      {:ok, app_build} ->
        :ok =
          Storage.multipart_complete_upload(
            AppBuilds.storage_key(%{
              account_handle: account_handle,
              project_handle: project_handle,
              app_build_id: app_build_id
            }),
            upload_id,
            Enum.map(parts, fn %{part_number: part_number, etag: etag} ->
              {part_number, etag}
            end),
            selected_project.account
          )

        AppBuilds.update_preview_with_app_build(app_build.preview.id, app_build)

        trigger_pending_qa_runs_for_app_build(app_build)

        Tuist.Analytics.preview_upload(Authentication.authenticated_subject(conn))

        {:ok, preview} =
          AppBuilds.preview_by_id(app_build.preview.id,
            preload: [:app_builds, :created_by_account]
          )

        conn
        |> put_status(:ok)
        |> json(map_preview(preview, account_handle, project_handle, selected_project.account))

      {:error, :not_found} ->
        conn
        |> put_status(:not_found)
        |> json(%{message: "Preview not found."})

      {:error, reason} ->
        conn
        |> put_status(:bad_request)
        |> json(%{message: reason})
    end
  end

  operation(:show,
    summary: "Returns a preview with a given id.",
    description: "This endpoint returns a preview with a given id, including the url to download the preview.",
    operation_id: "downloadPreview",
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
      preview_id: [
        in: :path,
        type: :string,
        required: true,
        description: "The id of the preview."
      ]
    ],
    responses: %{
      ok: {"The preview exists and can be downloaded", "application/json", Schemas.Preview},
      unauthorized: {"You need to be authenticated to access this resource", "application/json", Error},
      forbidden: {"The authenticated subject is not authorized to perform this action", "application/json", Error},
      not_found: {"The preview does not exist", "application/json", Error},
      bad_request: {"The request is invalid", "application/json", Error}
    }
  )

  def show(
        %{
          assigns: %{selected_project: selected_project},
          path_params: %{
            "account_handle" => account_handle,
            "project_handle" => project_handle,
            "preview_id" => preview_id
          },
          params: _params
        } = conn,
        _args
      ) do
    case AppBuilds.preview_by_id(preview_id, preload: [:app_builds, :created_by_account]) do
      {:ok, preview} ->
        Tuist.Analytics.preview_download(Authentication.authenticated_subject(conn))

        response = map_preview(preview, account_handle, project_handle, selected_project.account)

        response =
          if Enum.empty?(response.builds) do
            response
          else
            # Note: the URL field is deprecated but we still need to return to cater for older CLI versions
            %{response | url: hd(response.builds).url}
          end

        json(conn, response)

      {:error, :not_found} ->
        conn
        |> put_status(:not_found)
        |> json(%{message: "Preview not found."})

      {:error, reason} ->
        conn
        |> put_status(:bad_request)
        |> json(%{message: reason})
    end
  end

  operation(:index,
    summary: "List previews.",
    description: "This endpoint returns a list of previews for a given project.",
    operation_id: "listPreviews",
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
      display_name: [
        in: :query,
        type: :string,
        description: "The display name of previews."
      ],
      specifier: [
        in: :query,
        type: :string,
        description: "The preview version specifier. Currently, accepts a commit SHA, branch name, or latest."
      ],
      supported_platforms: [
        in: :query,
        type: %Schema{
          type: :array,
          items: PreviewSupportedPlatform,
          description: "The supported platforms of the preview."
        }
      ],
      page_size: [
        in: :query,
        type: %Schema{
          title: "PreviewIndexPageSize",
          description: "The maximum number of preview to return in a single page.",
          type: :integer,
          default: 10,
          minimum: 1,
          maximum: 20
        }
      ],
      page: [
        in: :query,
        type: %Schema{
          title: "PreviewIndexPage",
          description: "The page number to return.",
          type: :integer,
          default: 1,
          minimum: 1
        }
      ],
      distinct_field: [
        in: :query,
        type: %Schema{
          type: :string,
          enum: ["bundle_identifier"]
        },
        description: "Distinct fields – no two previews will be returned with this field having the same value."
      ]
    ],
    responses: %{
      ok:
        {"Successful response for listing previews.", "application/json",
         %Schema{
           title: "PreviewsIndex",
           type: :object,
           properties: %{
             previews: %Schema{
               description: "Previews list.",
               type: :array,
               items: Schemas.Preview
             },
             pagination_metadata: PaginationMetadata
           },
           required: [:previews, :pagination_metadata]
         }},
      unauthorized: {"You need to be authenticated to access this resource", "application/json", Error},
      forbidden: {"The authenticated subject is not authorized to perform this action", "application/json", Error}
    }
  )

  def index(
        %{
          assigns: %{selected_project: selected_project},
          params:
            %{account_handle: account_handle, project_handle: project_handle, page_size: page_size, page: page} = params
        } = conn,
        _params
      ) do
    filters = get_filters(selected_project, params)

    distinct =
      case Map.get(params, :distinct_field) do
        nil -> []
        field -> [String.to_atom(field)]
      end

    {previews, meta} =
      AppBuilds.list_previews(
        %{
          page: page,
          page_size: page_size,
          filters: filters,
          order_by: [:inserted_at],
          order_directions: [:desc]
        },
        distinct: distinct,
        supported_platforms: Map.get(params, :supported_platforms),
        preload: [:app_builds, :created_by_account]
      )

    json(conn, %{
      previews:
        Enum.map(
          previews,
          &map_preview(&1, account_handle, project_handle, selected_project.account)
        ),
      pagination_metadata: %{
        has_next_page: meta.has_next_page?,
        has_previous_page: meta.has_previous_page?,
        current_page: meta.current_page,
        page_size: meta.page_size,
        total_count: meta.total_count,
        total_pages: meta.total_pages
      }
    })
  end

  operation(:latest,
    summary: "Get the latest preview for a binary.",
    description:
      "Given a binary ID (Mach-O UUID) and build version (CFBundleVersion), returns the latest preview on the same track (bundle identifier and git branch). Returns nil if no matching build is found.",
    operation_id: "getLatestPreview",
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
      binary_id: [
        in: :query,
        type: :string,
        required: true,
        description: "The Mach-O UUID of the running binary."
      ],
      build_version: [
        in: :query,
        type: :string,
        required: true,
        description: "The CFBundleVersion of the running app."
      ]
    ],
    responses: %{
      ok:
        {"The latest preview on the same track, or null if not found.", "application/json",
         %Schema{
           title: "LatestPreviewResponse",
           type: :object,
           properties: %{
             preview: Schemas.Preview
           }
         }},
      unauthorized: {"You need to be authenticated to access this resource", "application/json", Error},
      forbidden: {"The authenticated subject is not authorized to perform this action", "application/json", Error}
    }
  )

  def latest(
        %{
          assigns: %{selected_project: selected_project},
          params: %{account_handle: account_handle, project_handle: project_handle, binary_id: binary_id} = params
        } = conn,
        _params
      ) do
    build_version = Map.get(params, :build_version)

    case AppBuilds.latest_preview_for_binary_id_and_build_version(binary_id, build_version, selected_project,
           preload: [:app_builds, :created_by_account]
         ) do
      {:ok, preview} ->
        json(conn, %{preview: map_preview(preview, account_handle, project_handle, selected_project.account)})

      {:error, :not_found} ->
        json(conn, %{preview: nil})
    end
  end

  defp get_filters(%Project{} = project, params) do
    specifier = Map.get(params, :specifier)

    filters = [
      %{field: :project_id, op: :==, value: project.id},
      %{field: :bundle_identifier, op: :not_empty, value: true}
    ]

    specifier_filters =
      cond do
        is_nil(specifier) -> []
        specifier == "latest" -> [%{field: :git_branch, op: :==, value: project.default_branch}]
        valid_git_commit_sha?(specifier) -> [%{field: :git_commit_sha, op: :==, value: specifier}]
        true -> [%{field: :git_branch, op: :==, value: specifier}]
      end

    filters = specifier_filters ++ filters

    filters =
      case Map.get(params, :display_name) do
        nil -> filters
        display_name -> [%{field: :display_name, op: :==, value: display_name} | filters]
      end

    filters
  end

  operation(:upload_icon,
    summary: "Uploads a preview icon.",
    description: "The endpoint uploads a preview icon.",
    operation_id: "uploadPreviewIcon",
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
      preview_id: [
        in: :path,
        type: :string,
        required: true,
        description: "The preview identifier."
      ]
    ],
    responses: %{
      ok: {"The presigned upload URL", "application/json", ArtifactUploadURL},
      unauthorized: {"You need to be authenticated to access this resource", "application/json", Error},
      forbidden: {"The authenticated subject is not authorized to perform this action", "application/json", Error},
      not_found: {"The project or preview doesn't exist", "application/json", Error}
    }
  )

  def upload_icon(
        %{
          assigns: %{selected_project: selected_project},
          params: %{account_handle: account_handle, project_handle: project_handle, preview_id: preview_id}
        } = conn,
        _params
      ) do
    case AppBuilds.preview_by_id(preview_id) do
      {:ok, preview} ->
        expires_in = 3600

        upload_url =
          Storage.generate_upload_url(
            AppBuilds.icon_storage_key(%{
              account_handle: account_handle,
              project_handle: project_handle,
              preview_id: preview.id
            }),
            selected_project.account,
            expires_in: expires_in
          )

        json(conn, %{url: upload_url, expires_at: System.system_time(:second) + expires_in})

      {:error, :not_found} ->
        conn
        |> put_status(:not_found)
        |> json(%{message: "Preview not found."})

      {:error, reason} ->
        conn
        |> put_status(:bad_request)
        |> json(%{message: reason})
    end
  end

  defp valid_git_commit_sha?(hash) do
    Regex.match?(~r/^[a-fA-F0-9]{40}$/, hash)
  end

  defp map_app_build(app_build, account_handle, project_handle, account, opts) do
    expires_in = Keyword.get(opts, :expires_in, 3600)

    key =
      AppBuilds.storage_key(%{
        account_handle: account_handle,
        project_handle: project_handle,
        app_build_id: app_build.id
      })

    %{
      id: app_build.id,
      url: Storage.generate_download_url(key, account, expires_in: expires_in),
      type: app_build.type,
      supported_platforms: app_build.supported_platforms,
      inserted_at: app_build.inserted_at,
      binary_id: app_build.binary_id,
      build_version: app_build.build_version
    }
  end

  operation(:delete,
    summary: "Deletes a preview.",
    description: "This endpoint deletes a preview with a given id.",
    operation_id: "deletePreview",
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
      preview_id: [
        in: :path,
        type: :string,
        required: true,
        description: "The id of the preview to delete."
      ]
    ],
    responses: %{
      no_content: "The preview was deleted",
      unauthorized: {"You need to be authenticated to access this resource", "application/json", Error},
      forbidden: {"The authenticated subject is not authorized to perform this action", "application/json", Error},
      not_found: {"The preview does not exist", "application/json", Error},
      bad_request: {"The request is invalid", "application/json", Error}
    }
  )

  def delete(
        %{
          path_params: %{
            "account_handle" => _account_handle,
            "project_handle" => _project_handle,
            "preview_id" => preview_id
          }
        } = conn,
        _params
      ) do
    case AppBuilds.preview_by_id(preview_id) do
      {:ok, preview} ->
        AppBuilds.delete_preview!(preview)

        conn
        |> put_status(:no_content)
        |> json(%{})

      {:error, :not_found} ->
        conn
        |> put_status(:not_found)
        |> json(%{message: "Preview not found."})

      {:error, reason} ->
        conn
        |> put_status(:bad_request)
        |> json(%{message: reason})
    end
  end

  defp map_preview(preview, account_handle, project_handle, account, opts \\ []) do
    builds =
      preview.app_builds
      |> Enum.map(&map_app_build(&1, account_handle, project_handle, account, opts))
      |> Enum.sort_by(& &1.inserted_at, {:desc, DateTime})

    %{
      id: preview.id,
      url: url(~p"/#{account_handle}/#{project_handle}/previews/#{preview.id}"),
      device_url:
        "itms-services://?action=download-manifest&url=#{url(~p"/#{account_handle}/#{project_handle}/previews/#{preview.id}/manifest.plist")}",
      qr_code_url: url(~p"/#{account_handle}/#{project_handle}/previews/#{preview.id}/qr-code.png"),
      icon_url: url(~p"/#{account_handle}/#{project_handle}/previews/#{preview.id}/icon.png"),
      version: preview.version,
      bundle_identifier: preview.bundle_identifier,
      display_name: preview.display_name,
      git_commit_sha: preview.git_commit_sha,
      git_branch: preview.git_branch,
      track: preview.track,
      builds: builds,
      supported_platforms: preview.supported_platforms,
      inserted_at: preview.inserted_at,
      created_by:
        preview.created_by_account &&
          %{
            id: preview.created_by_account.id,
            handle: preview.created_by_account.name
          },
      created_from_ci: is_nil(preview.created_by_account) || is_nil(preview.created_by_account.user_id)
    }
  end

  defp trigger_pending_qa_runs_for_app_build(app_build) do
    # We currently support QA only for the iOS simulator
    if :ios_simulator in app_build.supported_platforms do
      pending_qa_runs = QA.find_pending_qa_runs_for_app_build(app_build)

      for qa_run <- pending_qa_runs do
        {:ok, updated_qa_run} = QA.update_qa_run(qa_run, %{app_build_id: app_build.id})
        QA.enqueue_test_worker(updated_qa_run)
      end
    end
  end
end
