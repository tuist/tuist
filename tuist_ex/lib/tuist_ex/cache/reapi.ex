defmodule TuistEx.Cache.Reapi do
  @moduledoc false

  alias TuistEx.Analytics.Config
  alias TuistEx.Analytics.Isolated
  alias TuistEx.Analytics.Report
  alias TuistEx.Auth
  alias TuistEx.Cache.Reapi.ActionCache
  alias TuistEx.Cache.Reapi.ActionResult
  alias TuistEx.Cache.Reapi.ByteStream
  alias TuistEx.Cache.Reapi.Capabilities
  alias TuistEx.Cache.Reapi.Channel
  alias TuistEx.Cache.Reapi.Compression
  alias TuistEx.Cache.Reapi.Digest
  alias TuistEx.Cache.Reapi.GetActionResultRequest
  alias TuistEx.Cache.Reapi.GetCapabilitiesRequest
  alias TuistEx.Cache.Reapi.OutputFile
  alias TuistEx.Cache.Reapi.RequestMetadata
  alias TuistEx.Cache.Reapi.ToolDetails
  alias TuistEx.Cache.Reapi.UpdateActionResultRequest
  alias TuistEx.Cache.Store
  alias TuistEx.CertificateTrust
  alias TuistEx.HTTP

  @timeout 30_000
  @chunk_bytes 64 * 1024
  @inline_max_bytes 128 * 1024

  def with_session(options, invocation_id, analytics_options, callback) do
    reference = make_ref()

    session = fn ->
      case Process.get(reference, :unopened) do
        :unopened ->
          value =
            case open(options, invocation_id, analytics_options) do
              {:ok, value} -> value
              _ -> nil
            end

          Process.put(reference, value)
          value

        value ->
          value
      end
    end

    try do
      callback.(session)
    after
      close(Process.delete(reference))
    end
  end

  def open(options, invocation_id, analytics_options \\ [])
  def open(_options, nil, _analytics_options), do: nil

  def open(options, invocation_id, analytics_options) do
    if Keyword.get(options, :remote, true) do
      with {:ok, config} <- Config.resolve(analytics_options),
           {:ok, token} <- Auth.token(Keyword.put(analytics_options, :url, config.url)),
           {:ok, endpoint, allow_insecure?} <- endpoint(options, config, token, analytics_options),
           {:ok, 200, %{"token" => cache_token}} <-
             HTTP.request(
               :post,
               config.url <>
                 "/api/cache/token?" <>
                 URI.encode_query(%{
                   "full_handle" =>
                     config.project_handle.account <> "/" <> config.project_handle.project
                 }),
               %{},
               [{"authorization", "Bearer " <> token}]
             ) do
        connect(endpoint, cache_token, config.project_handle, invocation_id,
          allow_insecure: allow_insecure?
        )
      else
        _ -> nil
      end
    end
  rescue
    _ -> nil
  catch
    _, _ -> nil
  end

  defp endpoint(options, config, token, analytics_options) do
    environment = Keyword.get(analytics_options, :environment, &System.get_env/1)

    {override, allow_insecure?} =
      case environment.("TUIST_CACHE_ENDPOINT") do
        value when value in [nil, ""] -> {Keyword.get(options, :endpoint), false}
        value -> {value, true}
      end

    case override do
      url when is_binary(url) ->
        {:ok, url, allow_insecure?}

      _ ->
        url =
          config.url <>
            "/api/cache/endpoints?" <>
            URI.encode_query(%{"account_handle" => config.project_handle.account})

        case HTTP.request(:get, url, nil, [
               {"authorization", "Bearer " <> token},
               {"x-tuist-feature-flags", "kura"}
             ]) do
          {:ok, 200, %{"endpoints" => [endpoint | _]}} when is_binary(endpoint) ->
            {:ok, endpoint, false}

          _ ->
            {:error, :unavailable}
        end
    end
  end

  def connect(url, token, project, invocation_id, options \\ [])

  def connect(url, token, %{account: account, project: project}, invocation_id, options) do
    uri = URI.parse(url)

    if uri.scheme not in ["http", "https"] or is_nil(uri.host) or not is_nil(uri.userinfo) or
         not is_nil(uri.query) or not is_nil(uri.fragment) or uri.path not in [nil, "", "/"],
       do: throw(:invalid_endpoint)

    if uri.scheme == "http" and String.downcase(uri.host) not in ["localhost", "127.0.0.1", "::1"] and
         Keyword.get(options, :allow_insecure) != true,
       do: throw(:invalid_endpoint)

    restore_paths(:grpc, MapSet.new())
    {:ok, _} = Application.ensure_all_started(:tuist_ex)

    options = [
      adapter: GRPC.Client.Adapters.Mint,
      adapter_opts: [
        config_options: [hostname: uri.host],
        transport_opts: [timeout: 5_000, nodelay: true]
      ]
    ]

    options =
      if uri.scheme == "https" do
        ssl =
          Keyword.put(
            CertificateTrust.ssl_options(),
            :server_name_indication,
            String.to_charlist(uri.host)
          )

        Keyword.put(options, :cred, GRPC.Credential.new(ssl: ssl))
      else
        options
      end

    with {:ok, address} <- Isolated.run(fn -> resolve_address(uri) end, 5_000),
         {:ok, owner} <-
           DynamicSupervisor.start_child(
             TuistEx.Cache.Reapi.Supervisor,
             {Channel, {address, options, self()}}
           ) do
      channel = GenServer.call(owner, :channel)

      session = %{
        owner: owner,
        channel: channel,
        token: token,
        account: account,
        project: project,
        invocation_id: invocation_id
      }

      session = Map.put(session, :zstd, supports_zstd?(session))

      if connected?(session) do
        {:ok, session}
      else
        close(session)
        {:error, :unavailable}
      end
    end
  end

  def close(nil), do: :ok
  def close({:ok, session}), do: close(session)

  def close(session) do
    if Process.alive?(session.owner), do: GenServer.stop(session.owner)
    :ok
  rescue
    _ -> :ok
  catch
    :exit, _ -> :ok
  end

  # Bound both active RPCs and retained, decoded bundles in a prefetch window.
  def concurrency, do: 4

  def get_many(nil, _requests), do: %{}

  def get_many(session, requests) when length(requests) <= 4 do
    case Isolated.run(
           fn ->
             requests
             |> Task.async_stream(
               fn {key, dependency} = request -> {request, get(session, key, dependency)} end,
               max_concurrency: concurrency(),
               ordered: false,
               timeout: @timeout + 500,
               on_timeout: :kill_task
             )
             |> Enum.reduce(%{}, fn
               {:ok, {request, result}}, results -> Map.put(results, request, result)
               _, results -> results
             end)
           end,
           @timeout + 1_000
         ) do
      results when is_map(results) -> results
      _ -> %{}
    end
  end

  def get(session, key, dependency, timeout \\ @timeout)
  def get(nil, _key, _dependency, _timeout), do: :miss

  def get(session, key, dependency, timeout) do
    case run_rpc(session, fn -> get_result(session, key, dependency) end, timeout) do
      {:error, _} ->
        close(session)
        :miss

      result ->
        result
    end
  end

  defp get_result(session, key, dependency) do
    opts = request_options(session, key, dependency)

    request = %GetActionResultRequest{
      instance_name: session.project,
      action_digest: %Digest{hash: key},
      inline_output_files: ["*", "tuist-inline-max-bytes:#{@inline_max_bytes}"]
    }

    started = System.monotonic_time(:microsecond)

    with true <- connected?(session),
         {:ok,
          %ActionResult{
            exit_code: 0,
            output_files: [
              %OutputFile{path: "dependency.bundle", digest: digest, contents: contents}
            ]
          }} <- ActionCache.Stub.get_action_result(session.channel, request, opts),
         true <- valid_digest?(digest),
         {:ok, binary, metrics} <- read_output(session, digest, contents, opts, started) do
      {:ok, binary, Map.put(metrics, :output_digest, digest.hash)}
    else
      _ -> :miss
    end
  rescue
    _ -> :miss
  catch
    _, _ -> :miss
  end

  def put(session, key, dependency, binary, timeout \\ @timeout)
  def put(nil, _key, _dependency, _binary, _timeout), do: {:error, :unavailable}

  def put(session, key, dependency, binary, timeout) when byte_size(binary) <= 64 * 1024 * 1024 do
    case run_rpc(session, fn -> put_result(session, key, dependency, binary) end, timeout) do
      {:error, :timeout} = error ->
        close(session)
        error

      result ->
        result
    end
  end

  def put(_session, _key, _dependency, _binary, _timeout), do: {:error, :invalid_blob}

  defp put_result(session, key, dependency, binary) do
    if not connected?(session), do: throw(:unavailable)
    digest = %Digest{hash: content_digest(binary), size_bytes: byte_size(binary)}
    opts = request_options(session, key, dependency)
    started = System.monotonic_time(:microsecond)

    {wire, compressed?} =
      if session.zstd and Compression.eligible?(byte_size(binary)),
        do: Compression.compress(binary),
        else: {binary, false}

    stream = ByteStream.Stub.write(session.channel, opts)
    encoding = if compressed?, do: "compressed-blobs/zstd/", else: "blobs/"

    resource =
      session.project <>
        "/uploads/" <>
        Report.id() <>
        "/" <> encoding <> digest.hash <> "/" <> to_string(digest.size_bytes)

    stream = write_chunks(stream, resource, wire, 0)

    case GRPC.Stub.recv(stream, timeout: @timeout) do
      {:ok, %Google.Bytestream.WriteResponse{committed_size: size}}
      when size == byte_size(wire) or (compressed? and size == -1) ->
        duration = System.monotonic_time(:microsecond) - started

        result = %ActionResult{
          output_files: [%OutputFile{path: "dependency.bundle", digest: digest}]
        }

        request = %UpdateActionResultRequest{
          instance_name: session.project,
          action_digest: %Digest{hash: key},
          action_result: result
        }

        case ActionCache.Stub.update_action_result(session.channel, request, opts) do
          {:ok, _} ->
            {:ok,
             %{
               output_digest: digest.hash,
               write_bytes: byte_size(binary),
               write_duration_us: duration,
               write_source: "remote"
             }}

          _ ->
            {:error, :unavailable}
        end

      _ ->
        {:error, :unavailable}
    end
  rescue
    _ -> {:error, :unavailable}
  catch
    _, _ -> {:error, :unavailable}
  end

  defp supports_zstd?(session) do
    if Compression.available?() do
      result =
        run_rpc(
          session,
          fn ->
            Capabilities.Stub.get_capabilities(
              session.channel,
              %GetCapabilitiesRequest{instance_name: session.project},
              request_options(session, "", "")
            )
          end,
          5_000
        )

      case result do
        {:ok, %{cache_capabilities: %{supported_compressors: compressors}}} ->
          1 in compressors

        {:error, :timeout} ->
          close(session)
          false

        _ ->
          false
      end
    else
      false
    end
  end

  defp run_rpc(session, callback, timeout) do
    Isolated.run(
      fn ->
        result = callback.()
        # Mint can reply to terminal headers before finishing its :done callback.
        # Keep the RPC process (and its linked stream handler) alive until then.
        if connected?(session),
          do: :sys.get_state(session.channel.adapter_payload.conn_pid, @timeout)

        result
      end,
      timeout
    )
  end

  defp connected?(session), do: Process.alive?(session.channel.adapter_payload.conn_pid)

  defp write_chunks(stream, resource, binary, offset) when byte_size(binary) <= @chunk_bytes do
    GRPC.Stub.send_request(
      stream,
      %Google.Bytestream.WriteRequest{
        resource_name: resource,
        data: binary,
        write_offset: offset,
        finish_write: true
      },
      end_stream: true
    )
  end

  defp write_chunks(stream, resource, <<chunk::binary-size(@chunk_bytes), rest::binary>>, offset) do
    stream =
      GRPC.Stub.send_request(stream, %Google.Bytestream.WriteRequest{
        resource_name: resource,
        data: chunk,
        write_offset: offset
      })

    write_chunks(stream, resource, rest, offset + @chunk_bytes)
  end

  defp read_output(session, digest, "", opts, _started), do: read_blob(session, digest, opts)

  defp read_output(session, digest, binary, _opts, started),
    do: verified_blob(session, digest, binary, started)

  defp verified_blob(session, digest, binary, started) do
    if byte_size(binary) == digest.size_bytes and content_digest(binary) == digest.hash do
      {:ok, binary,
       %{
         read_bytes: byte_size(binary),
         read_duration_us: System.monotonic_time(:microsecond) - started,
         read_source: "remote"
       }}
    else
      close(session)
      {:error, :invalid_blob}
    end
  end

  defp read_blob(session, digest, opts) do
    compressed? = session.zstd and Compression.eligible?(digest.size_bytes)

    case read_blob(session, digest, opts, compressed?) do
      {:error, %GRPC.RPCError{status: 12}} when compressed? ->
        read_blob(session, digest, opts, false)

      result ->
        result
    end
  end

  defp read_blob(session, digest, opts, compressed?) do
    started = System.monotonic_time(:microsecond)
    encoding = if compressed?, do: "compressed-blobs/zstd/", else: "blobs/"
    limit = if compressed?, do: Compression.wire_limit(digest.size_bytes), else: digest.size_bytes

    request = %Google.Bytestream.ReadRequest{
      resource_name:
        session.project <> "/" <> encoding <> digest.hash <> "/" <> to_string(digest.size_bytes)
    }

    with {:ok, stream} <- ByteStream.Stub.read(session.channel, request, opts) do
      try do
        {chunks, _wire_size, error} =
          Enum.reduce(stream, {[], 0, nil}, fn
            {:ok, %Google.Bytestream.ReadResponse{data: data}}, {chunks, size, error} ->
              size = size + byte_size(data)

              if size > limit or
                   System.monotonic_time(:microsecond) - started > @timeout * 1_000,
                 do: throw(:invalid_blob)

              {if(is_nil(error), do: [data | chunks], else: []), size, error}

            {:error, error}, {_chunks, size, _error} ->
              {[], size, error}

            _, _ ->
              throw(:invalid_blob)
          end)

        wire = chunks |> Enum.reverse() |> IO.iodata_to_binary()

        binary =
          if compressed? and is_nil(error),
            do: Compression.decompress(wire, digest.size_bytes),
            else: wire

        if is_nil(error),
          do: verified_blob(session, digest, binary, started),
          else: {:error, error}
      rescue
        _ ->
          close(session)
          {:error, :invalid_blob}
      catch
        _, _ ->
          close(session)
          {:error, :invalid_blob}
      end
    end
  end

  def resolve_address(uri, resolver \\ &:inet.getaddr/2) do
    host = String.to_charlist(uri.host)

    with {:error, _} <- resolver.(host, :inet),
         {:error, _} <- resolver.(host, :inet6) do
      {:error, :unavailable}
    else
      {:ok, address} ->
        ip = address |> :inet.ntoa() |> to_string()
        target = if tuple_size(address) == 8, do: "ipv6:[#{ip}]", else: "ipv4:#{ip}"
        {:ok, "#{target}:#{uri.port}"}
    end
  end

  # REAPI hashes raw CAS bytes, not the deterministic term encoding used for input keys.
  defp content_digest(binary), do: :crypto.hash(:sha256, binary) |> Base.encode16(case: :lower)

  defp valid_digest?(%Digest{hash: hash, size_bytes: size}),
    do: size > 0 and size <= Store.max_bundle_bytes() and Regex.match?(~r/\A[0-9a-f]{64}\z/, hash)

  defp valid_digest?(_), do: false

  defp request_options(session, key, dependency) do
    metadata = %RequestMetadata{
      tool_details: %ToolDetails{
        tool_name: "mix",
        tool_version: to_string(Application.spec(:tuist_ex, :vsn) || "unknown")
      },
      tool_invocation_id: session.invocation_id,
      action_id: key,
      action_mnemonic: "MixCompile",
      target_id: to_string(dependency)
    }

    [
      timeout: @timeout,
      metadata: %{
        "authorization" => "Bearer " <> session.token,
        "x-tuist-account-handle" => session.account,
        "build.bazel.remote.execution.v2.requestmetadata-bin" => RequestMetadata.encode(metadata)
      }
    ]
  end

  defp restore_paths(app, visited) do
    if MapSet.member?(visited, app) do
      visited
    else
      path = Path.join([Mix.Project.build_path(), "lib", to_string(app), "ebin"])
      if File.dir?(path), do: Code.prepend_path(path), else: Mix.ensure_application!(app)
      Application.load(app)
      visited = MapSet.put(visited, app)

      applications =
        (Application.spec(app, :applications) || []) --
          (Application.spec(app, :optional_applications) || [])

      Enum.reduce(applications, visited, &restore_paths/2)
    end
  end
end
