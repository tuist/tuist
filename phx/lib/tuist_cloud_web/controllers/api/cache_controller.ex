defmodule TuistCloudWeb.API.CacheController do
  use OpenApiSpex.ControllerSpecs
  use TuistCloudWeb, :controller
  alias TuistCloud.Storage
  alias OpenApiSpex.Schema

  plug(OpenApiSpex.Plug.CastAndValidate,
    json_render_error_v2: true,
    render_error: TuistCloudWeb.RenderAPIErrorPlug
  )

  plug(TuistCloudWeb.API.EnsureProjectPresencePlug)
  plug(TuistCloudWeb.API.Authorization.CachePlug, :cache)
  plug(TuistCloudWeb.EnsureValidAccountPlanPlug)

  defmodule Error do
    require OpenApiSpex

    OpenApiSpex.schema(%{
      type: :object,
      properties: %{
        message: %Schema{
          type: :string
        }
      }
    })
  end

  operation(:download,
    summary: "Downloads an artifact from the cache.",
    description:
      "This endpoint returns a signed URL that can be used to download an artifact from the cache.",
    parameters: [
      cache_category: [
        in: :query,
        type: %Schema{type: :string, enum: ["tests", "builds"], default: "builds"},
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
        {"The artifact exists and is downloadable", "application/json",
         %Schema{
           title: "Cache artifacth download URL",
           description: "The URL to download the artifact from the cache.",
           type: :object,
           properties: %{
             status: %Schema{type: :string, default: "success"},
             data: %Schema{
               type: :object,
               properties: %{
                 url: %Schema{
                   type: :string,
                   description: "The URL to download the artifact from the cache."
                 },
                 expires_at: %Schema{
                   type: :integer,
                   description: "The UNIX timestamp when the URL expires."
                 }
               }
             }
           }
         }},
      forbidden:
        {"The authenticated subject is not authorized to perform this action", "application/json",
         Error},
      not_found: {"The project or the cache artifact doesn't exist", "application/json", Error}
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

    url =
      Storage.generate_download_url(
        %{
          hash: hash,
          name: name,
          project_slug: project_slug,
          cache_category: cache_category
        },
        expires_in: expires_in
      )

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
    deprecated: true,
    parameters: [
      cache_category: [
        in: :query,
        type: %Schema{type: :string, enum: ["tests", "builds"], default: "builds"},
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
           title: "Cache artifact existence",
           description: "The artifact exists in the cache and can be downloaded",
           type: :object,
           properties: %{
             status: %Schema{type: :string, default: "success"},
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
           title: "Absent cache artifact",
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
         }}
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
      Storage.exists(%{
        hash: hash,
        name: name,
        project_slug: project_slug,
        cache_category: cache_category
      })

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
    parameters: [
      cache_category: [
        in: :query,
        type: %Schema{type: :string, enum: ["tests", "builds"], default: "builds"},
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
        {"The upload has been started", "application/json",
         %Schema{
           title: "Cache artifact upload ID",
           description:
             "The upload has been initiated and a ID is returned to upload the various parts using multi-part uploads",
           type: :object,
           properties: %{
             status: %Schema{type: :string, default: "success"},
             data: %Schema{
               type: :object,
               properties: %{
                 upload_id: %Schema{type: :string, description: "The upload ID"}
               }
             }
           }
         }},
      forbidden:
        {"The authenticated subject is not authorized to perform this action", "application/json",
         Error},
      not_found: {"The project doesn't exist", "application/json", Error}
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
      Storage.multipart_start(%{
        hash: hash,
        name: name,
        project_slug: project_slug,
        cache_category: cache_category
      })

    conn |> json(%{status: "success", data: %{upload_id: upload_id}})
  end

  def multipart_start(conn, _params) do
    conn |> put_status(400) |> json(%{message: "The request has missing or invalid parameters"})
  end

  operation(:multipart_generate_url,
    summary: "It generates a signed URL for uploading a part.",
    description:
      "Given an upload ID and a part number, this endpoint returns a signed URL that can be used to upload a part of a multipart upload. The URL is short-lived and expires in 120 seconds.",
    parameters: [
      cache_category: [
        in: :query,
        type: %Schema{type: :string, enum: ["tests", "builds"], default: "builds"},
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
      ok:
        {"The URL has been generated", "application/json",
         %Schema{
           title: "Cache artifact multi-part part upload URL",
           description: "The URL to upload a part has been generated.",
           type: :object,
           properties: %{
             status: %Schema{type: :string, default: "success"},
             data: %Schema{
               type: :object,
               properties: %{
                 url: %Schema{type: :string, description: "The URL to upload the part"}
               }
             }
           }
         }},
      forbidden:
        {"The authenticated subject is not authorized to perform this action", "application/json",
         Error},
      not_found: {"The project doesn't exist", "application/json", Error}
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
      Storage.generate_multipart_upload_url(
        %{
          hash: hash,
          name: name,
          project_slug: project_slug,
          cache_category: cache_category
        },
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
        type: %Schema{type: :string, enum: ["tests", "builds"], default: "builds"},
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
           title: "Cache artifact multi-part upload completion",
           description:
             "This response confirms that the upload has been completed successfully. The cache will now be able to serve the artifact.",
           type: :object,
           properties: %{
             status: %Schema{type: :string, default: "success"},
             data: %Schema{
               type: :object,
               properties: %{}
             }
           }
         }},
      forbidden:
        {"The authenticated subject is not authorized to perform this action", "application/json",
         Error},
      not_found: {"The project doesn't exist", "application/json", Error}
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
    :ok =
      Storage.complete_multipart_upload(
        %{
          hash: hash,
          name: name,
          project_slug: project_slug,
          cache_category: cache_category
        },
        upload_id,
        parts
        |> Enum.map(fn %{part_number: part_number, etag: etag} ->
          {part_number, etag}
        end)
      )

    conn |> json(%{status: "success", data: %{}})
  end

  def multipart_complete(conn, _params) do
    conn |> put_status(400) |> json(%{message: "The request has missing or invalid parameters"})
  end
end
