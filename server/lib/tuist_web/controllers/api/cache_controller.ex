defmodule TuistWeb.API.CacheController do
  use OpenApiSpex.ControllerSpecs
  use TuistWeb, :controller

  alias OpenApiSpex.Schema
  alias Tuist.Accounts
  alias Tuist.API.Pipeline
  alias Tuist.CacheActionItems
  alias Tuist.Storage
  alias TuistWeb.API.Schemas
  alias TuistWeb.API.Schemas.ArtifactMultipartUploadUrl
  alias TuistWeb.API.Schemas.ArtifactUploadId
  alias TuistWeb.API.Schemas.CacheArtifactDownloadURL
  alias TuistWeb.API.Schemas.CacheCategory
  alias TuistWeb.API.Schemas.Error

  plug(
    OpenApiSpex.Plug.CastAndValidate,
    json_render_error_v2: true,
    render_error: TuistWeb.RenderAPIErrorPlug
  )

  plug TuistWeb.Plugs.LoaderPlug when action not in [:endpoints]

  plug TuistWeb.API.Authorization.AuthorizationPlug,
       [
         category: :cache,
         caching: true,
         cache_ttl: to_timeout(minute: 1)
       ]
       when action not in [:endpoints]

  plug TuistWeb.API.Authorization.BillingPlug when action not in [:endpoints]

  plug :sign

  tags(["Cache"])

  operation(:endpoints,
    summary: "Get cache endpoints.",
    description: "Returns custom cache endpoints if configured for the account, otherwise returns default endpoints.",
    operation_id: "getCacheEndpoints",
    parameters: [
      account_handle: [
        in: :query,
        type: :string,
        required: false,
        description: "The name of the account to get custom cache endpoints for."
      ]
    ],
    responses: %{
      ok:
        {"List of cache endpoints", "application/json",
         %Schema{
           title: "CacheEndpoints",
           description: "List of available cache endpoints",
           type: :object,
           required: [:endpoints],
           properties: %{
             endpoints: %Schema{
               type: :array,
               items: %Schema{type: :string}
             }
           }
         }}
    }
  )

  def endpoints(conn, params) do
    endpoints = Accounts.get_cache_endpoints_for_handle(params[:account_handle])
    json(conn, %{endpoints: endpoints})
  end

  operation(:get_cache_action_item,
    summary: "Get a cache action item.",
    description: "This endpoint gets an item from the action cache.",
    operation_id: "getCacheActionItem",
    parameters: [
      account_handle: [
        in: :path,
        type: :string,
        required: true,
        description: "The name of the account that the project belongs to."
      ],
      project_handle: [
        in: :path,
        type: :string,
        required: true,
        description: "The name of the project the cache action item belongs to."
      ],
      hash: [
        in: :path,
        type: :string,
        required: true,
        description: "The hash that uniquely identifies an item in the action cache."
      ]
    ],
    responses: %{
      ok: {"The item exists in the action cache", "application/json", Schemas.CacheActionItem},
      not_found: {"The item doesn't exist in the actino cache", "application/json", Error},
      unauthorized: {"You need to be authenticated to access this resource", "application/json", Error},
      forbidden: {"The authenticated subject is not authorized to perform this action", "application/json", Error},
      payment_required: {"The account has an invalid plan", "application/json", Error}
    }
  )

  def get_cache_action_item(%{assigns: %{selected_project: selected_project}} = conn, %{hash: hash} = _params) do
    cache_action_item =
      Tuist.KeyValueStore.get_or_update(
        [
          Atom.to_string(__MODULE__),
          "get_cache_action_item",
          selected_project.id,
          hash
        ],
        [
          ttl: Map.get(conn.assigns, :cache_ttl, to_timeout(minute: 1)),
          cache: Map.get(conn.assigns, :cache, :tuist),
          locking: true
        ],
        fn ->
          CacheActionItems.get_cache_action_item(%{
            project: selected_project,
            hash: hash
          })
        end
      )

    if is_nil(cache_action_item) do
      conn
      |> put_status(:not_found)
      |> json(%{message: "The item doesn't exist in the cache."})
    else
      conn
      |> put_status(:ok)
      |> json(%{
        hash: cache_action_item.hash
      })
    end
  end

  operation(:download,
    summary: "Downloads an artifact from the cache.",
    description: "This endpoint returns a signed URL that can be used to download an artifact from the cache.",
    operation_id: "downloadCacheArtifact",
    parameters: [
      cache_category: [
        in: :query,
        type: CacheCategory,
        required: false,
        description: "The category of the cache. It's used to differentiate between different types of caches."
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
      ok: {"The artifact exists and is downloadable", "application/json", CacheArtifactDownloadURL},
      unauthorized: {"You need to be authenticated to access this resource", "application/json", Error},
      forbidden: {"The authenticated subject is not authorized to perform this action", "application/json", Error},
      not_found: {"The project or the cache artifact doesn't exist", "application/json", Error},
      payment_required: {"The account has an invalid plan", "application/json", Error}
    }
  )

  def download(
        %{
          assigns: %{selected_project: selected_project},
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
        selected_project.account,
        expires_in: expires_in
      )

    expires_at = System.system_time(:second) + expires_in
    json(conn, %{status: "success", data: %{url: url, expires_at: expires_at}})
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
        description: "The category of the cache. It's used to differentiate between different types of caches."
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
      unauthorized: {"You need to be authenticated to access this resource", "application/json", Error},
      forbidden: {"The authenticated subject is not authorized to perform this action", "application/json", Error},
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
          assigns: %{selected_project: selected_project},
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
      Storage.object_exists?(
        get_object_key(%{
          hash: hash,
          name: name,
          project_slug: project_slug,
          cache_category: cache_category
        }),
        selected_project.account
      )

    if exists do
      json(conn, %{status: "success", data: %{}})
    else
      conn
      |> put_status(404)
      |> json(%{errors: [%{message: "The artifact was not found", code: "not_found"}]})
    end
  end

  def exists(conn, _params) do
    conn |> put_status(400) |> json(%{message: "The request has missing or invalid parameters"})
  end

  operation(:upload_cache_action_item,
    summary: "It uploads a given cache action item.",
    description:
      "The endpoint caches a given action item without uploading a file. To upload files, use the multipart upload instead.",
    operation_id: "uploadCacheActionItem",
    parameters: [
      account_handle: [
        in: :path,
        type: :string,
        required: true,
        description: "The name of the account that the project belongs to."
      ],
      project_handle: [
        in: :path,
        type: :string,
        required: true,
        description: "The name of the project to clean cache for"
      ]
    ],
    request_body:
      {"Cache action item upload params", "application/json",
       %Schema{
         title: "CacheActionItemUploadParams",
         type: :object,
         properties: %{
           hash: %Schema{type: :string, description: "The hash of the cache action item."}
         }
       }},
    responses: %{
      created: {"The action item was cached", "application/json", Schemas.CacheActionItem},
      ok: {"The request is valid but the cache action item already exists", "application/json", Schemas.CacheActionItem},
      bad_request: {"The request has missing or invalid parameters", "application/json", Error},
      unauthorized: {"You need to be authenticated to access this resource", "application/json", Error},
      forbidden: {"The authenticated subject is not authorized to perform this action", "application/json", Error},
      not_found: {"The project doesn't exist", "application/json", Error},
      payment_required: {"The account has an invalid plan", "application/json", Error}
    }
  )

  def upload_cache_action_item(
        %{assigns: %{selected_project: selected_project}, body_params: %{hash: hash}} = conn,
        _params
      ) do
    cache_action_item =
      Tuist.KeyValueStore.get_or_update(
        [
          Atom.to_string(__MODULE__),
          "upload_cache_action_item",
          selected_project.id,
          hash
        ],
        [
          ttl: Map.get(conn.assigns, :cache_ttl, to_timeout(minute: 1)),
          cache: Map.get(conn.assigns, :cache, :tuist),
          locking: true
        ],
        fn ->
          CacheActionItems.get_cache_action_item(%{
            project: selected_project,
            hash: hash
          })
        end
      )

    cond do
      is_nil(cache_action_item) ->
        :ok =
          Pipeline.async_push(
            {:create_cache_action_item,
             %{
               project_id: selected_project.id,
               hash: hash,
               inserted_at: DateTime.utc_now(:second),
               updated_at: DateTime.utc_now(:second)
             }}
          )

        conn
        |> put_status(:created)
        |> json(%{
          hash: hash
        })

      conn |> get_req_header("x-tuist-cli-version") |> List.first() == "4.28.0" ->
        conn
        |> put_status(:created)
        |> json(%{
          hash: hash
        })

      true ->
        conn
        |> put_status(:ok)
        |> json(%{hash: cache_action_item.hash})
    end
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
        description: "The category of the cache. It's used to differentiate between different types of caches."
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
      unauthorized: {"You need to be authenticated to access this resource", "application/json", Error},
      forbidden: {"The authenticated subject is not authorized to perform this action", "application/json", Error},
      not_found: {"The project doesn't exist", "application/json", Error},
      payment_required: {"The account has an invalid plan", "application/json", Error}
    }
  )

  def multipart_start(
        %{
          assigns: %{selected_project: selected_project},
          query_params: %{
            "hash" => hash,
            "name" => name,
            "project_id" => project_slug,
            "cache_category" => cache_category
          }
        } = conn,
        _params
      ) do
    json(conn, %{
      status: "success",
      data: %{
        upload_id:
          Storage.multipart_start(
            get_object_key(%{
              hash: hash,
              name: name,
              project_slug: project_slug,
              cache_category: cache_category
            }),
            selected_project.account
          )
      }
    })
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
        description: "The category of the cache. It's used to differentiate between different types of caches."
      ],
      content_length: [
        in: :query,
        type: :integer,
        required: false,
        description: "The size in bytes of the part that will be uploaded. It's used to generate the signed URL."
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
      unauthorized: {"You need to be authenticated to access this resource", "application/json", Error},
      forbidden: {"The authenticated subject is not authorized to perform this action", "application/json", Error},
      not_found: {"The project doesn't exist", "application/json", Error},
      payment_required: {"The account has an invalid plan", "application/json", Error}
    }
  )

  def multipart_generate_url(
        %{
          assigns: %{selected_project: selected_project},
          query_params:
            %{
              "hash" => hash,
              "name" => name,
              "project_id" => project_slug,
              "part_number" => part_number,
              "upload_id" => upload_id,
              "cache_category" => cache_category
            } = params
        } = conn,
        _params
      ) do
    expires_in = 120
    content_length = Map.get(params, "content_length")

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
        selected_project.account,
        expires_in: expires_in,
        content_length: if(is_nil(content_length), do: nil, else: String.to_integer(content_length))
      )

    json(conn, %{status: "success", data: %{url: url}})
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
        description: "The category of the cache. It's used to differentiate between different types of caches."
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
      unauthorized: {"You need to be authenticated to access this resource", "application/json", Error},
      forbidden: {"The authenticated subject is not authorized to perform this action", "application/json", Error},
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
          body_params: %{parts: parts},
          assigns: %{selected_project: selected_project}
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
        Enum.map(parts, fn %{part_number: part_number, etag: etag} ->
          {part_number, etag}
        end),
        selected_project.account
      )

    json(conn, %{status: "success", data: %{}})
  end

  def multipart_complete(conn, _params) do
    conn |> put_status(400) |> json(%{message: "The request has missing or invalid parameters"})
  end

  operation(:clean,
    summary: "Cleans cache for a given project",
    operation_id: "cleanCache",
    parameters: [
      account_handle: [
        in: :path,
        type: :string,
        required: true,
        description: "The name of the account that the project belongs to."
      ],
      project_handle: [
        in: :path,
        type: :string,
        required: true,
        description: "The name of the project to clean cache for"
      ]
    ],
    responses: %{
      no_content: "The cache has been successfully cleaned",
      unauthorized: {"You need to be authenticated to access this resource", "application/json", Error},
      forbidden: {"The authenticated subject is not authorized to perform this action", "application/json", Error},
      not_found: {"The project was not found", "application/json", Error}
    }
  )

  def clean(%{assigns: %{selected_project: %{id: project_id}}} = conn, _params) do
    %{
      project_id: project_id
    }
    |> Tuist.Projects.Workers.CleanProjectWorker.new()
    |> Oban.insert!()

    send_resp(conn, :no_content, "")
  end

  defp get_object_key(%{hash: hash, cache_category: cache_category, name: name, project_slug: project_slug}) do
    if cache_category == nil do
      "#{String.downcase(project_slug)}/#{hash}/#{name}"
    else
      "#{String.downcase(project_slug)}/#{cache_category}/#{hash}/#{name}"
    end
  end

  defp sign(%{query_params: %{"hash" => hash}} = conn, _opts) do
    sign_conn(conn, hash)
  end

  defp sign(%{path_params: %{"hash" => hash}} = conn, _opts) do
    sign_conn(conn, hash)
  end

  defp sign(conn, _opts) do
    conn
  end

  defp sign_conn(conn, hash) do
    if Tuist.Environment.test?() or Tuist.Environment.dev?() do
      put_resp_header(conn, "x-tuist-signature", "tuist")
    else
      put_resp_header(conn, "x-tuist-signature", Tuist.License.sign(hash))
    end
  end
end
