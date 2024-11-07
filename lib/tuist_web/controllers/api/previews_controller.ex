defmodule TuistWeb.API.PreviewsController do
  alias TuistWeb.API.Schemas
  alias Tuist.CommandEvents
  alias TuistWeb.API.Schemas.ArtifactDownloadURL
  alias TuistWeb.API.EnsureProjectPresencePlug
  alias Tuist.Previews
  alias Tuist.Previews.Preview
  alias TuistWeb.Authentication

  alias TuistWeb.API.Schemas.{
    ArtifactMultipartUploadParts,
    ArtifactMultipartUploadUrl,
    ArtifactMultipartUploadPart,
    Error
  }

  alias Tuist.Storage
  alias OpenApiSpex.Schema
  use OpenApiSpex.ControllerSpecs
  use TuistWeb, :controller

  plug(OpenApiSpex.Plug.CastAndValidate,
    json_render_error_v2: true,
    render_error: TuistWeb.RenderAPIErrorPlug
  )

  plug(EnsureProjectPresencePlug)
  plug(TuistWeb.API.Authorization.AuthorizationPlug, :preview)

  tags ["Previews"]

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
                 preview_id: %Schema{type: :string, description: "The id of the preview."}
               },
               required: [:upload_id, :preview_id]
             }
           },
           required: [:status, :data]
         }},
      unauthorized:
        {"You need to be authenticated to access this resource", "application/json", Error},
      forbidden:
        {"The authenticated subject is not authorized to perform this action", "application/json",
         Error},
      not_found: {"The project doesn't exist", "application/json", Error}
    }
  )

  def multipart_start(
        %{body_params: body_params} = conn,
        _params
      ) do
    project =
      EnsureProjectPresencePlug.get_project(conn)

    %Preview{id: preview_id} =
      Previews.create_preview(%{
        project: project,
        type: Map.get(body_params, :type) |> String.to_atom(),
        display_name: Map.get(body_params, :display_name),
        bundle_identifier: Map.get(body_params, :bundle_identifier),
        version: Map.get(body_params, :version)
      })

    upload_id = Storage.multipart_start(get_object_key(conn, preview_id))

    conn
    |> json(%{status: "success", data: %{upload_id: upload_id, preview_id: preview_id}})
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
             description: "The id of the preview."
           }
         },
         required: [:multipart_upload_part, :preview_id]
       }},
    responses: %{
      ok: {"The URL has been generated", "application/json", ArtifactMultipartUploadUrl},
      unauthorized:
        {"You need to be authenticated to access this resource", "application/json", Error},
      forbidden:
        {"The authenticated subject is not authorized to perform this action", "application/json",
         Error},
      not_found: {"The project doesn't exist", "application/json", Error}
    }
  )

  def multipart_generate_url(
        %{
          body_params: %{
            preview_id: preview_id,
            multipart_upload_part:
              %{
                "part_number" => part_number,
                "upload_id" => upload_id
              } = multipart_upload_part
          }
        } = conn,
        _params
      ) do
    expires_in = 120
    content_length = Map.get(multipart_upload_part, "content_length")

    url =
      Storage.multipart_generate_url(
        get_object_key(conn, preview_id),
        upload_id,
        part_number,
        expires_in: expires_in,
        content_length: content_length
      )

    conn |> json(%{status: "success", data: %{url: url}})
  end

  operation(:multipart_complete,
    summary: "It completes a multi-part upload.",
    description:
      "Given the upload ID and all the parts with their ETags, this endpoint completes the multipart upload.",
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
             description: "The id of the preview."
           }
         },
         required: [:multipart_upload_parts, :preview_id]
       }},
    responses: %{
      ok: {"The upload has been completed", "application/json", TuistWeb.API.Schemas.Preview},
      unauthorized:
        {"You need to be authenticated to access this resource", "application/json", Error},
      forbidden:
        {"The authenticated subject is not authorized to perform this action", "application/json",
         Error},
      not_found: {"The project or preview doesn't exist", "application/json", Error}
    }
  )

  def multipart_complete(
        %{
          path_params: %{
            "account_handle" => account_handle,
            "project_handle" => project_handle
          },
          body_params: %{
            preview_id: preview_id,
            multipart_upload_parts: %ArtifactMultipartUploadParts{
              parts: parts,
              upload_id: upload_id
            }
          }
        } = conn,
        _params
      ) do
    preview = Previews.get_preview_by_id(preview_id)

    if is_nil(preview) do
      conn
      |> put_status(:not_found)
      |> json(%{message: "Preview not found."})
    else
      :ok =
        Storage.multipart_complete_upload(
          get_object_key(conn, preview_id),
          upload_id,
          parts
          |> Enum.map(fn %{part_number: part_number, etag: etag} ->
            {part_number, etag}
          end)
        )

      Tuist.Analytics.preview_upload(Authentication.authenticated_subject(conn))

      conn
      |> put_status(:ok)
      |> json(%{
        id: preview_id,
        url: url(~p"/#{account_handle}/#{project_handle}/previews/#{preview_id}"),
        qr_code_url:
          url(~p"/#{account_handle}/#{project_handle}/previews/#{preview_id}/qr-code.svg"),
        bundle_identifier: preview.bundle_identifier,
        display_name: preview.display_name
      })
    end
  end

  operation(:download,
    summary: "Downloads a preview.",
    description: "This endpoint returns a signed URL that can be used to download a preview.",
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
      ok: {"The preview exists and can be downloaded", "application/json", ArtifactDownloadURL},
      unauthorized:
        {"You need to be authenticated to access this resource", "application/json", Error},
      forbidden:
        {"The authenticated subject is not authorized to perform this action", "application/json",
         Error},
      not_found: {"The build doesn't exist", "application/json", Error}
    }
  )

  def download(
        %{
          path_params: %{
            "preview_id" => preview_id
          }
        } = conn,
        _params
      ) do
    expires_in = 3600

    url =
      Storage.generate_download_url(
        get_object_key(conn, preview_id),
        expires_in: expires_in
      )

    expires_at = System.system_time(:second) + expires_in
    Tuist.Analytics.preview_download(Authentication.authenticated_subject(conn))
    conn |> json(%{url: url, expires_at: expires_at})
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
        description:
          "The preview version specifier. Currently, accepts a commit SHA, branch name, or latest."
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
        description:
          "Distinct fields – no two previews will be returned with this field having the same value."
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
             }
           },
           required: [:previews]
         }},
      unauthorized:
        {"You need to be authenticated to access this resource", "application/json", Error},
      forbidden:
        {"The authenticated subject is not authorized to perform this action", "application/json",
         Error}
    }
  )

  def index(
        %{
          params:
            %{
              account_handle: account_handle,
              project_handle: project_handle,
              page_size: page_size,
              page: page
            } = params
        } =
          conn,
        _params
      ) do
    project =
      EnsureProjectPresencePlug.get_project(conn)

    specifier = Map.get(params, :specifier)

    filters = [
      %{field: :project_id, op: :==, value: project.id},
      %{field: :name, op: :==, value: "share"},
      %{field: :preview_id, op: :not_empty, value: true},
      %{field: :preview_bundle_identifier, op: :not_empty, value: true}
    ]

    specifier_filters =
      cond do
        is_nil(specifier) -> []
        specifier == "latest" -> [%{field: :git_branch, op: :==, value: project.default_branch}]
        valid_git_commit_sha?(specifier) -> [%{field: :git_commit_sha, op: :==, value: specifier}]
        true -> [%{field: :git_branch, op: :==, value: specifier}]
      end

    filters = specifier_filters ++ filters

    display_name = Map.get(params, :display_name)

    filters =
      case display_name do
        nil -> filters
        _ -> [%{field: :preview_display_name, op: :==, value: display_name} | filters]
      end

    distinct =
      case Map.get(params, :distinct_field) do
        nil -> []
        field -> [preview: [field |> String.to_atom()]]
      end

    {command_events, _meta} =
      CommandEvents.list_command_events(
        %{
          page: page,
          page_size: page_size,
          filters: filters,
          order_by: [:created_at],
          order_directions: [:desc]
        },
        preload: [:preview],
        distinct: distinct
      )

    conn
    |> json(%{
      previews:
        command_events
        |> Enum.map(
          &%{
            id: &1.preview.id,
            url: url(~p"/#{account_handle}/#{project_handle}/previews/#{&1.preview.id}"),
            qr_code_url:
              url(~p"/#{account_handle}/#{project_handle}/previews/#{&1.preview.id}/qr-code.svg"),
            bundle_identifier: &1.preview.bundle_identifier,
            display_name: &1.preview.display_name
          }
        )
    })
  end

  defp valid_git_commit_sha?(hash) do
    Regex.match?(~r/^[a-fA-F0-9]{40}$/, hash)
  end

  defp get_object_key(
         %{
           path_params: %{
             "account_handle" => account_handle,
             "project_handle" => project_handle
           }
         } = _conn,
         preview_id
       ) do
    Previews.get_storage_key(%{
      account_handle: account_handle,
      project_handle: project_handle,
      preview_id: preview_id
    })
  end
end
