defmodule XcodeProcessor.XCResultProcessor do
  @moduledoc false

  require Logger

  def process_local(archive_path, opts \\ []) do
    bucket = Keyword.get(opts, :s3_bucket) || XcodeProcessor.Environment.s3_bucket()
    temp_dir = make_temp_dir()

    try do
      result = process_archive(archive_path, temp_dir)

      with {:ok, parsed_data} <- result do
        upload_attachments(parsed_data, bucket, opts)
      end
    after
      cleanup_temp(temp_dir)
    end
  end

  def process(storage_key, opts \\ []) do
    bucket = XcodeProcessor.Environment.s3_bucket()
    temp_dir = make_temp_dir()
    archive_path = Path.join(temp_dir, "xcresult-archive")

    try do
      :telemetry.span([:xcode_processor, :xcresult], %{}, fn ->
        download_result =
          :telemetry.span([:xcode_processor, :s3, :download], %{}, fn ->
            case ExAws.S3.download_file(bucket, storage_key, archive_path) |> ExAws.request() do
              {:ok, _} ->
                file_size = File.stat!(archive_path).size
                {:ok, %{file_size: file_size}}

              {:error, reason} ->
                {{:error, reason}, %{}}
            end
          end)

        result =
          case download_result do
            {:error, _} = error ->
              error

            _ ->
              result = process_archive(archive_path, temp_dir)

              with {:ok, parsed_data} <- result do
                upload_attachments(parsed_data, bucket, opts)
              end
          end

        status = if match?({:ok, _}, result), do: :ok, else: :error
        {result, %{status: status}}
      end)
    after
      cleanup_temp(temp_dir)
    end
  end

  defp process_archive(archive_path, temp_dir) do
    with :ok <- extract_archive(archive_path, temp_dir),
         xcresult_path when not is_nil(xcresult_path) <- find_xcresult(temp_dir) do
      parse_xcresult(xcresult_path, Path.dirname(xcresult_path))
    else
      nil -> {:error, :xcresult_not_found}
      {:error, _} = error -> error
    end
  end

  # Callers upload either a PKZIP archive (legacy CLI clients) or an
  # AppleArchive payload (newer CLI clients — faster via LZFSE). Sniff the
  # magic bytes and dispatch: Erlang's `:zip` for PKZIP, the Swift NIF
  # (AppleArchive framework) for everything else.
  @pkzip_magic <<0x50, 0x4B>>

  defp extract_archive(archive_path, temp_dir) do
    case File.open(archive_path, [:read, :binary], fn file -> IO.binread(file, 2) end) do
      {:ok, @pkzip_magic} ->
        case :zip.unzip(~c"#{archive_path}", [{:cwd, ~c"#{temp_dir}"}]) do
          {:ok, _} -> :ok
          {:error, reason} -> {:error, {:zip_unzip_failed, reason}}
        end

      {:ok, _} ->
        XcodeProcessor.XCResultNIF.decompress_archive(archive_path, temp_dir)

      {:error, reason} ->
        {:error, {:archive_read_failed, reason}}
    end
  end

  defp parse_xcresult(xcresult_path, root_dir) do
    :telemetry.span([:xcode_processor, :xcresult, :parse], %{}, fn ->
      result = XcodeProcessor.XCResultNIF.parse(xcresult_path, root_dir)
      status = if match?({:ok, _}, result), do: :ok, else: :error
      {result, %{status: status}}
    end)
  end

  defp upload_attachments(parsed_data, bucket, opts) do
    account_handle = Keyword.get(opts, :account_handle)
    project_handle = Keyword.get(opts, :project_handle)
    test_run_id = Keyword.get(opts, :test_run_id)

    if is_nil(account_handle) or is_nil(project_handle) or is_nil(test_run_id) do
      {:ok, parsed_data}
    else
      # Collect all attachments, upload in parallel, build a lookup by file_path
      all_attachments =
        parsed_data
        |> Map.get("test_modules", [])
        |> Enum.flat_map(&Map.get(&1, "test_cases", []))
        |> Enum.flat_map(&Map.get(&1, "attachments", []))

      uploaded_map =
        all_attachments
        |> Task.async_stream(
          &upload_attachment(&1, bucket, account_handle, project_handle, test_run_id),
          max_concurrency: 30,
          timeout: 60_000,
          on_timeout: :kill_task
        )
        |> Enum.zip(all_attachments)
        |> Enum.reduce(%{}, fn
          {{:ok, {:ok, uploaded}}, original}, acc ->
            Map.put(acc, original["file_path"], uploaded)

          {{:ok, :error}, original}, acc ->
            Logger.error("Failed to upload attachment: #{original["file_name"]}")
            acc

          {{:exit, reason}, original}, acc ->
            Logger.error(
              "Attachment upload task crashed for #{original["file_name"]}: #{inspect(reason)}"
            )

            acc
        end)

      # Replace attachments in-place using the lookup
      test_modules =
        parsed_data
        |> Map.get("test_modules", [])
        |> Enum.map(&replace_attachments(&1, uploaded_map))

      {:ok, Map.put(parsed_data, "test_modules", test_modules)}
    end
  end

  defp replace_attachments(module, uploaded_map) do
    Map.update(module, "test_cases", [], fn test_cases ->
      Enum.map(test_cases, &replace_test_case_attachments(&1, uploaded_map))
    end)
  end

  defp replace_test_case_attachments(test_case, uploaded_map) do
    Map.update(test_case, "attachments", [], fn attachments ->
      Enum.flat_map(attachments, fn att ->
        case Map.fetch(uploaded_map, att["file_path"]) do
          {:ok, uploaded} -> [uploaded]
          :error -> []
        end
      end)
    end)
  end

  defp upload_attachment(attachment, bucket, account_handle, project_handle, test_run_id) do
    file_path = Map.get(attachment, "file_path")
    file_name = Map.get(attachment, "file_name")
    attachment_id = Ecto.UUID.generate()

    if file_path && File.exists?(file_path) do
      s3_key =
        "#{String.downcase(account_handle)}/#{String.downcase(project_handle)}/tests/runs/#{test_run_id}/attachments/#{attachment_id}/#{file_name}"

      case file_path
           |> ExAws.S3.Upload.stream_file()
           |> ExAws.S3.upload(bucket, s3_key)
           |> ExAws.request() do
        {:ok, _} ->
          uploaded =
            attachment
            |> Map.delete("file_path")
            |> Map.put("attachment_id", attachment_id)

          {:ok, uploaded}

        {:error, reason} ->
          Logger.error("Failed to upload attachment #{file_name}: #{inspect(reason)}")
          :error
      end
    else
      :error
    end
  end

  defp make_temp_dir do
    temp_dir =
      Path.join(System.tmp_dir!(), "xcode_processor_#{:erlang.unique_integer([:positive])}")

    File.mkdir_p!(temp_dir)
    temp_dir
  end

  defp find_xcresult(temp_dir) do
    temp_dir
    |> Path.join("**/*.xcresult")
    |> Path.wildcard()
    |> List.first()
  end

  defp cleanup_temp(temp_dir) do
    {:ok, _} = File.rm_rf(temp_dir)
    :ok
  end
end
