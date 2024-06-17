defmodule TuistCloudWeb.API.CacheController do
  use OpenApiSpex.ControllerSpecs
  use TuistCloudWeb, :controller
  alias TuistCloudWeb.API.Schemas.ArtifactMultipartUploadUrl
  alias TuistCloudWeb.API.Schemas.ArtifactUploadId
  alias TuistCloudWeb.API.EnsureProjectPresencePlug
  alias TuistCloud.Storage
  alias TuistCloud.CommandEvents
  alias OpenApiSpex.Schema
  alias TuistCloudWeb.API.Schemas.{Error, CacheArtifactDownloadURL, CacheCategory}

  plug(OpenApiSpex.Plug.CastAndValidate,
    json_render_error_v2: true,
    render_error: TuistCloudWeb.RenderAPIErrorPlug
  )

  plug(TuistCloudWeb.API.EnsureProjectPresencePlug)
  plug(TuistCloudWeb.API.Authorization.AuthorizationPlug, :cache)
  plug(TuistCloudWeb.API.Authorization.BillingPlug)

  operation(:download,
    summary: "Downloads an artifact from the cache.",
    description:
      "This endpoint returns a signed URL that can be used to download an artifact from the cache.",
    operation_id: "downloadCacheArtifact",
    parameters: [
      cache_category: [
        in: :query,
        type: CacheCategory,
        required: false,
        description:
          "The category of the cache. It's used to differentiate between different types of caches."
      ],
      project_id: [
        in: :query,
        type: :string,
        required: true,
        description: "The project identifier '{account_name}/{project_name}'."
      ],
      hash: [
        in: :query,
        type: :string,
        required: true,
        description: "The hash that uniquely identifies the artifact in the cache."
      ],
      name: [in: :query, type: :string, required: true, description: "The name of the artifact."]
    ],
    responses: %{
      ok:
        {"The artifact exists and is downloadable", "application/json", CacheArtifactDownloadURL},
      forbidden:
        {"The authenticated subject is not authorized to perform this action", "application/json",
         Error},
      not_found: {"The project or the cache artifact doesn't exist", "application/json", Error},
      payment_required: {"The account has an invalid plan", "application/json", Error}
    }
  )

  def download(
        %{
          query_params: %{
            "hash" => hash,
            "name" => name,
            "project_id" => project_slug,
            "cache_category" => cache_category
          }
        } = conn,
        _params
      ) do
    expires_in = 3600

    item = %{
      hash: hash,
      name: name,
      project_slug: project_slug,
      cache_category: cache_category
    }

    url =
      Storage.generate_download_url(
        get_object_key(item),
        expires_in: expires_in
      )

    upload_event = CommandEvents.get_cache_event(%{hash: hash, event_type: :upload})

    unless is_nil(upload_event) do
      CommandEvents.create_cache_event(%{
        name: name,
        event_type: :download,
        size: upload_event.size,
        project_id: EnsureProjectPresencePlug.get_project(conn).id,
        hash: hash
      })
    end

    expires_at = System.system_time(:second) + expires_in
    conn |> json(%{status: "success", data: %{url: url, expires_at: expires_at}})
  end

  def download(conn, _params) do
    conn |> put_status(400) |> json(%{message: "The request has missing or invalid parameters"})
  end

  operation(:exists,
    summary: "It checks if an artifact exists in the cache.",
    description:
      "This endpoint checks if an artifact exists in the cache. It returns a 404 status code if the artifact does not exist.",
    operation_id: "cacheArtifactExists",
    deprecated: true,
    parameters: [
      cache_category: [
        in: :query,
        type: CacheCategory,
        required: false,
        description:
          "The category of the cache. It's used to differentiate between different types of caches."
      ],
      project_id: [
        in: :query,
        type: :string,
        required: true,
        description: "The project identifier '{account_name}/{project_name}'."
      ],
      hash: [
        in: :query,
        type: :string,
        required: true,
        description: "The hash that uniquely identifies the artifact in the cache."
      ],
      name: [in: :query, type: :string, required: true, description: "The name of the artifact."]
    ],
    responses: %{
      ok:
        {"The artifact exists", "application/json",
         %Schema{
           title: "CacheArtifactExistence",
           description: "The artifact exists in the cache and can be downloaded",
           type: :object,
           properties: %{
             status: %Schema{type: :string, default: "success", enum: ["success"]},
             data: %Schema{
               type: :object,
               properties: %{}
             }
           }
         }},
      forbidden:
        {"The authenticated subject is not authorized to perform this action", "application/json",
         Error},
      not_found:
        {"The artifact doesn't exist", "application/json",
         %Schema{
           title: "AbsentCacheArtifact",
           type: :object,
           properties: %{
             error: %Schema{
               type: :array,
               items: %Schema{
                 type: :object,
                 properties: %{
                   message: %Schema{type: :string},
                   code: %Schema{type: :string, default: "not_found"}
                 }
               }
             }
           }
         }},
      payment_required: {"The account has an invalid plan", "application/json", Error}
    }
  )

  def exists(
        %{
          query_params: %{
            "hash" => hash,
            "name" => name,
            "project_id" => project_slug,
            "cache_category" => cache_category
          }
        } = conn,
        _params
      ) do
    exists =
      Storage.exists(
        get_object_key(%{
          hash: hash,
          name: name,
          project_slug: project_slug,
          cache_category: cache_category
        })
      )

    if exists do
      conn |> json(%{status: "success", data: %{}})
    else
      conn
      |> put_status(404)
      |> json(%{errors: [%{message: "S3 object was not found", code: "not_found"}]})
    end
  end

  def exists(conn, _params) do
    conn |> put_status(400) |> json(%{message: "The request has missing or invalid parameters"})
  end

  operation(:multipart_start,
    summary: "It initiates a multipart upload in the cache.",
    description:
      "The endpoint returns an upload ID that can be used to generate URLs for the individual parts and complete the upload.",
    operation_id: "startCacheArtifactMultipartUpload",
    parameters: [
      cache_category: [
        in: :query,
        type: CacheCategory,
        required: false,
        description:
          "The category of the cache. It's used to differentiate between different types of caches."
      ],
      project_id: [
        in: :query,
        type: :string,
        required: true,
        description: "The project identifier '{account_name}/{project_name}'."
      ],
      hash: [
        in: :query,
        type: :string,
        required: true,
        description: "The hash that uniquely identifies the artifact in the cache."
      ],
      name: [in: :query, type: :string, required: true, description: "The name of the artifact."]
    ],
    responses: %{
      ok: {"The upload has been started", "application/json", ArtifactUploadId},
      forbidden:
        {"The authenticated subject is not authorized to perform this action", "application/json",
         Error},
      not_found: {"The project doesn't exist", "application/json", Error},
      payment_required: {"The account has an invalid plan", "application/json", Error}
    }
  )

  def multipart_start(
        %{
          query_params: %{
            "hash" => hash,
            "name" => name,
            "project_id" => project_slug,
            "cache_category" => cache_category
          }
        } = conn,
        _params
      ) do
    upload_id =
      Storage.multipart_start(
        get_object_key(%{
          hash: hash,
          name: name,
          project_slug: project_slug,
          cache_category: cache_category
        })
      )

    conn |> json(%{status: "success", data: %{upload_id: upload_id}})
  end

  def multipart_start(conn, _params) do
    conn |> put_status(400) |> json(%{message: "The request has missing or invalid parameters"})
  end

  operation(:multipart_generate_url,
    summary: "It generates a signed URL for uploading a part.",
    description:
      "Given an upload ID and a part number, this endpoint returns a signed URL that can be used to upload a part of a multipart upload. The URL is short-lived and expires in 120 seconds.",
    operation_id: "generateCacheArtifactMultipartUploadURL",
    parameters: [
      cache_category: [
        in: :query,
        type: CacheCategory,
        required: false,
        description:
          "The category of the cache. It's used to differentiate between different types of caches."
      ],
      project_id: [
        in: :query,
        type: :string,
        required: true,
        description: "The project identifier '{account_name}/{project_name}'."
      ],
      hash: [
        in: :query,
        type: :string,
        required: true,
        description: "The hash that uniquely identifies the artifact in the cache."
      ],
      part_number: [
        in: :query,
        type: :integer,
        required: true,
        description: "The part number of the multipart upload."
      ],
      upload_id: [
        in: :query,
        type: :string,
        required: true,
        description: "The upload ID."
      ],
      name: [in: :query, type: :string, required: true, description: "The name of the artifact."]
    ],
    responses: %{
      ok: {"The URL has been generated", "application/json", ArtifactMultipartUploadUrl},
      forbidden:
        {"The authenticated subject is not authorized to perform this action", "application/json",
         Error},
      not_found: {"The project doesn't exist", "application/json", Error},
      payment_required: {"The account has an invalid plan", "application/json", Error}
    }
  )

  def multipart_generate_url(
        %{
          query_params: %{
            "hash" => hash,
            "name" => name,
            "project_id" => project_slug,
            "part_number" => part_number,
            "upload_id" => upload_id,
            "cache_category" => cache_category
          }
        } = conn,
        _params
      ) do
    expires_in = 120

    url =
      Storage.multipart_generate_url(
        get_object_key(%{
          hash: hash,
          name: name,
          project_slug: project_slug,
          cache_category: cache_category
        }),
        upload_id,
        part_number,
        expires_in: expires_in
      )

    conn |> json(%{status: "success", data: %{url: url}})
  end

  def multipart_generate_url(conn, _params) do
    conn |> put_status(400) |> json(%{message: "The request has missing or invalid parameters"})
  end

  operation(:multipart_complete,
    summary: "It completes a multi-part upload.",
    description:
      "Given the upload ID and all the parts with their ETags, this endpoint completes the multipart upload. The cache will then be able to serve the artifact.",
    operation_id: "completeCacheArtifactMultipartUpload",
    request_body:
      {"Multi-part upload parts", "application/json",
       %Schema{
         type: :object,
         properties: %{
           parts: %Schema{
             type: :array,
             items: %Schema{
               type: :object,
               properties: %{
                 part_number: %Schema{type: :integer, description: "The part number"},
                 etag: %Schema{type: :string, description: "The ETag of the part"}
               }
             }
           }
         }
       }},
    parameters: [
      cache_category: [
        in: :query,
        type: CacheCategory,
        required: false,
        description:
          "The category of the cache. It's used to differentiate between different types of caches."
      ],
      project_id: [
        in: :query,
        type: :string,
        required: true,
        description: "The project identifier '{account_name}/{project_name}'."
      ],
      hash: [
        in: :query,
        type: :string,
        required: true,
        description: "The hash that uniquely identifies the artifact in the cache."
      ],
      upload_id: [
        in: :query,
        type: :string,
        required: true,
        description: "The upload ID."
      ],
      name: [in: :query, type: :string, required: true, description: "The name of the artifact."]
    ],
    responses: %{
      ok:
        {"The upload has been completed", "application/json",
         %Schema{
           title: "CacheArtifactMultipartUploadCompletion",
           description:
             "This response confirms that the upload has been completed successfully. The cache will now be able to serve the artifact.",
           type: :object,
           properties: %{
             status: %Schema{type: :string, default: "success", enum: ["success"]},
             data: %Schema{
               type: :object,
               properties: %{}
             }
           }
         }},
      forbidden:
        {"The authenticated subject is not authorized to perform this action", "application/json",
         Error},
      not_found: {"The project doesn't exist", "application/json", Error},
      payment_required: {"The account has an invalid plan", "application/json", Error}
    }
  )

  def multipart_complete(
        %{
          query_params: %{
            "hash" => hash,
            "name" => name,
            "project_id" => project_slug,
            "upload_id" => upload_id,
            "cache_category" => cache_category
          },
          body_params: %{
            parts: parts
          }
        } = conn,
        _params
      ) do
    item = %{
      hash: hash,
      name: name,
      project_slug: project_slug,
      cache_category: cache_category
    }

    :ok =
      Storage.multipart_complete_upload(
        get_object_key(item),
        upload_id,
        parts
        |> Enum.map(fn %{part_number: part_number, etag: etag} ->
          {part_number, etag}
        end)
      )

    CommandEvents.create_cache_event(%{
      name: name,
      event_type: :upload,
      size: Storage.size(get_object_key(item)),
      project_id: EnsureProjectPresencePlug.get_project(conn).id,
      hash: hash
    })

    conn |> json(%{status: "success", data: %{}})
  end

  def multipart_complete(conn, _params) do
    conn |> put_status(400) |> json(%{message: "The request has missing or invalid parameters"})
  end

  operation(:clean,
    summary: "Cleans cache for a given project",
    operation_id: "cleanCache",
    parameters: [
      account_name: [
        in: :path,
        type: :string,
        required: true,
        description: "The name of the account that the project belongs to."
      ],
      project_name: [
        in: :path,
        type: :string,
        required: true,
        description: "The name of the project to clean cache for"
      ]
    ],
    responses: %{
      no_content: "The cache has been successfully cleaned",
      forbidden:
        {"The authenticated subject is not authorized to perform this action", "application/json",
         Error},
      not_found: {"The project was not found", "application/json", Error}
    }
  )

  def clean(
        %{
          path_params: %{
            "account_name" => account_name,
            "project_name" => project_name
          }
        } = conn,
        _params
      ) do
    project_slug = "#{account_name}/#{project_name}"
    Storage.delete_all_objects("#{project_slug}/builds")
    Storage.delete_all_objects("#{project_slug}/tests")

    conn
    |> send_resp(:no_content, "")
  end

  defp get_object_key(%{
         hash: hash,
         cache_category: cache_category,
         name: name,
         project_slug: project_slug
       }) do
    if cache_category != nil do
      "#{project_slug}/#{cache_category}/#{hash}/#{name}"
    else
      "#{project_slug}/#{hash}/#{name}"
    end
  end
end
