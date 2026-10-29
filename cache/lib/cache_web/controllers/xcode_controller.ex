defmodule CacheWeb.XcodeController do
  use CacheWeb, :controller
  use OpenApiSpex.ControllerSpecs

  alias Cache.BodyReader
  alias Cache.CacheArtifacts
  alias Cache.Config
  alias Cache.S3
  alias Cache.S3Transfers
  alias Cache.Xcode
  alias CacheWeb.API.Schemas.Error
  alias CacheWeb.API.Schemas.SafePathComponent

  require Logger

  @max_upload_bytes 25 * 1024 * 1024

  plug OpenApiSpex.Plug.CastAndValidate,
    json_render_error_v2: true

  tags(["Xcode"])

  # Kura, the regional implementation of these cache routes, sheds a read it
  # cannot admit a response stream for instead of queueing it unboundedly. This
  # app never returns it, but clients see one contract across both
  # implementations, and a client that reads the shed as an unknown failure
  # gives up the retry the server explicitly asked for.
  @too_many_requests %OpenApiSpex.Response{
    description: "The server is limiting concurrent artifact response streams; retry after the hint",
    headers: %{
      "retry-after" => %OpenApiSpex.Header{
        description:
          "Whole seconds to wait before retrying. Jittered, so clients shed together do not return together.",
        schema: %OpenApiSpex.Schema{type: :string}
      }
    },
    content: %{
      "application/json" => %OpenApiSpex.MediaType{schema: Error}
    }
  }

  # Kura serves these reads directly and honours a single `bytes=` range on
  # them, so a download that dies partway can ask for the tail instead of the
  # whole artifact again. This app answers from nginx via `x-accel-redirect`,
  # which serves ranges itself, so both implementations satisfy the contract
  # even though neither resolves the header in Elixir. Declaring it here is what
  # lets the generated client issue a typed range request and read a 206 or a
  # 416 as the documented outcomes they are, rather than as undocumented
  # responses it has to guess at.
  @range_parameters [
    range: [
      in: :header,
      schema: %OpenApiSpex.Schema{type: :string},
      required: false,
      description: "A single byte range, as `bytes=<first>-`, to resume an interrupted download"
    ],
    "if-range": [
      in: :header,
      schema: %OpenApiSpex.Schema{type: :string},
      required: false,
      description:
        "The `ETag` the interrupted download started from. The range is honoured only while it still matches, and the whole artifact is returned otherwise, so a resume cannot splice two versions together."
    ]
  ]

  @partial_content %OpenApiSpex.Response{
    description: "The requested range of the artifact",
    headers: %{
      "content-range" => %OpenApiSpex.Header{
        description: "The range served, as `bytes <first>-<last>/<total>`",
        schema: %OpenApiSpex.Schema{type: :string}
      },
      "etag" => %OpenApiSpex.Header{
        description: "The representation served, to be echoed in `If-Range` when resuming",
        schema: %OpenApiSpex.Schema{type: :string}
      }
    },
    content: %{
      "application/octet-stream" => %OpenApiSpex.MediaType{}
    }
  }

  @range_not_satisfiable %OpenApiSpex.Response{
    description: "The requested range lies entirely outside the artifact",
    headers: %{
      "content-range" => %OpenApiSpex.Header{
        description: "The artifact's length, as `bytes */<total>`",
        schema: %OpenApiSpex.Schema{type: :string}
      }
    },
    content: %{
      "application/json" => %OpenApiSpex.MediaType{schema: Error}
    }
  }

  operation(:download,
    summary: "Download a Xcode cache artifact",
    operation_id: "downloadXcodeArtifact",
    parameters:
      [
        id: [
          in: :path,
          schema: SafePathComponent.schema(),
          required: true,
          description: "The artifact identifier"
        ],
        account_handle: [
          in: :query,
          schema: SafePathComponent.schema(),
          required: true,
          description: "The handle of the account"
        ],
        project_handle: [
          in: :query,
          schema: SafePathComponent.schema(),
          required: true,
          description: "The handle of the project"
        ]
      ] ++ @range_parameters,
    responses: %{
      ok: {"Artifact content", "application/octet-stream", nil},
      partial_content: @partial_content,
      requested_range_not_satisfiable: @range_not_satisfiable,
      not_found: {"Artifact not found", "application/json", Error},
      unprocessable_entity: {"Invalid request parameters", "application/json", Error},
      unauthorized: {"Unauthorized", "application/json", Error},
      forbidden: {"Forbidden", "application/json", Error},
      payment_required: {"The account has exhausted its plan's free tier", "application/json", Error},
      too_many_requests: @too_many_requests
    }
  )

  def download(conn, %{id: id, account_handle: account_handle, project_handle: project_handle}) do
    :telemetry.execute([:cache, :xcode, :download, :request], %{}, %{})
    key = Xcode.Disk.key(account_handle, project_handle, id)

    # Tracked before the stat on purpose: on a miss, enqueue_xcode_download/3 may
    # hydrate the file from S3 outside this request, and the row created here is
    # what keeps the hydrated file visible to eviction and safe from the orphan
    # scan. Moving this into the hit branch would orphan hydrated artifacts.
    :ok = CacheArtifacts.track_artifact_access(key)

    case Xcode.Disk.stat(account_handle, project_handle, id) do
      {:ok, %File.Stat{size: size}} ->
        local_path = Xcode.Disk.local_accel_path(account_handle, project_handle, id)

        :telemetry.execute([:cache, :xcode, :download, :disk_hit], %{size: size}, %{
          cas_id: id,
          account_handle: account_handle,
          project_handle: project_handle
        })

        conn
        |> put_resp_header("x-accel-redirect", local_path)
        |> send_resp(:ok, "")

      {:error, _} ->
        :telemetry.execute([:cache, :xcode, :download, :disk_miss], %{}, %{})

        enqueue_xcode_download(account_handle, project_handle, key)

        case S3.presign_download_url(key, type: :xcode_cache) do
          {:ok, url} ->
            conn
            |> put_resp_header("x-accel-redirect", S3.remote_accel_path(url))
            |> send_resp(:ok, "")

          {:error, reason} ->
            Sentry.capture_message("Failed to presign S3 url",
              extra: %{
                key: key,
                reason: reason
              }
            )

            :telemetry.execute([:cache, :xcode, :download, :error], %{}, %{reason: inspect(reason)})

            send_resp(conn, :not_found, "")
        end
    end
  end

  operation(:save,
    summary: "Save a Xcode cache artifact",
    operation_id: "saveXcodeArtifact",
    parameters: [
      id: [
        in: :path,
        schema: SafePathComponent.schema(),
        required: true,
        description: "The artifact identifier"
      ],
      account_handle: [
        in: :query,
        schema: SafePathComponent.schema(),
        required: true,
        description: "The handle of the account"
      ],
      project_handle: [
        in: :query,
        schema: SafePathComponent.schema(),
        required: true,
        description: "The handle of the project"
      ]
    ],
    request_body: {"The Xcode cache artifact data", "application/octet-stream", nil, required: true},
    responses: %{
      no_content: {"Upload successful", nil, nil},
      request_entity_too_large: {"Request body exceeded allowed size", "application/json", Error},
      request_timeout: {"Request body read timed out", "application/json", Error},
      internal_server_error: {"Failed to persist artifact", "application/json", Error},
      unprocessable_entity: {"Invalid request parameters", "application/json", Error},
      unauthorized: {"Unauthorized", "application/json", Error},
      forbidden: {"Forbidden", "application/json", Error},
      payment_required: {"The account has exhausted its plan's free tier", "application/json", Error}
    }
  )

  def save(conn, %{id: id, account_handle: account_handle, project_handle: project_handle}) do
    if Xcode.Disk.exists?(account_handle, project_handle, id) do
      handle_existing_artifact(conn)
    else
      save_new_artifact(conn, account_handle, project_handle, id)
    end
  end

  defp handle_existing_artifact(conn) do
    :telemetry.execute([:cache, :xcode, :upload, :exists], %{count: 1}, %{})

    {_, conn_after} = BodyReader.drain(conn, max_bytes: @max_upload_bytes)
    send_resp(conn_after, :no_content, "")
  end

  defp save_new_artifact(conn, account_handle, project_handle, id) do
    case Xcode.Disk.ensure_artifact_directory(account_handle, project_handle, id) do
      {:ok, target_dir} ->
        case BodyReader.read(conn, max_bytes: @max_upload_bytes, tmp_dir: target_dir) do
          {:ok, data, conn_after} ->
            size = get_data_size(data)
            :telemetry.execute([:cache, :xcode, :upload, :attempt], %{size: size}, %{})
            persist_artifact(conn_after, account_handle, project_handle, id, data, size)

          {:error, :too_large, conn_after} ->
            :telemetry.execute([:cache, :xcode, :upload, :error], %{count: 1}, %{reason: :too_large})
            send_error(conn_after, :request_entity_too_large, "Request body exceeded allowed size")

          {:error, :timeout, conn_after} ->
            :telemetry.execute([:cache, :xcode, :upload, :error], %{count: 1}, %{reason: :timeout})
            send_error(conn_after, :request_timeout, "Request body read timed out")

          {:error, :cancelled, conn_after} ->
            :telemetry.execute([:cache, :xcode, :upload, :cancelled], %{count: 1}, %{})
            send_resp(conn_after, :no_content, "")

          {:error, _reason, conn_after} ->
            :telemetry.execute([:cache, :xcode, :upload, :error], %{count: 1}, %{reason: :read_error})
            send_error(conn_after, :internal_server_error, "Failed to persist artifact")
        end

      {:error, reason} ->
        Logger.error("Failed to ensure Xcode cache artifact directory: #{inspect(reason)}")
        :telemetry.execute([:cache, :xcode, :upload, :error], %{count: 1}, %{reason: :persist_error})
        send_error(conn, :internal_server_error, "Failed to persist artifact")
    end
  end

  defp persist_artifact(conn, account_handle, project_handle, id, data, size) do
    case Xcode.Disk.put(account_handle, project_handle, id, data) do
      :ok ->
        :telemetry.execute([:cache, :xcode, :upload, :success], %{size: size}, %{
          cas_id: id,
          account_handle: account_handle,
          project_handle: project_handle
        })

        key = Xcode.Disk.key(account_handle, project_handle, id)
        :ok = CacheArtifacts.track_artifact_access(key)
        enqueue_xcode_upload_if_missing(account_handle, project_handle, key)
        send_resp(conn, :no_content, "")

      {:error, :exists} ->
        cleanup_tmp_file(data)
        :telemetry.execute([:cache, :xcode, :upload, :exists], %{count: 1}, %{})
        send_resp(conn, :no_content, "")

      {:error, _reason} ->
        cleanup_tmp_file(data)
        :telemetry.execute([:cache, :xcode, :upload, :error], %{count: 1}, %{reason: :persist_error})
        send_error(conn, :internal_server_error, "Failed to persist artifact")
    end
  end

  defp send_error(conn, status, message) do
    conn
    |> put_status(status)
    |> json(%{message: message})
  end

  defp cleanup_tmp_file({:file, tmp_path}), do: File.rm(tmp_path)
  defp cleanup_tmp_file(_binary_data), do: :ok

  defp enqueue_xcode_download(account_handle, project_handle, key) do
    if Config.xcode_database_interactions_enabled?() do
      S3Transfers.enqueue_xcode_download(account_handle, project_handle, key)
    end
  end

  defp enqueue_xcode_upload_if_missing(account_handle, project_handle, key) do
    if Config.xcode_database_interactions_enabled?() do
      S3Transfers.enqueue_upload_if_missing(account_handle, project_handle, :xcode_cache, key)
    end
  end

  defp get_data_size({:file, tmp_path}) do
    case File.stat(tmp_path) do
      {:ok, %File.Stat{size: sz}} -> sz
      _ -> 0
    end
  end

  defp get_data_size(bin) when is_binary(bin), do: byte_size(bin)
end
