defmodule Tuist.Processor.XCResultProcessor do
  @moduledoc """
  Parses xcresult test archives.

  The server's `ProcessXcresultWorker` Oban job is the only caller: it
  downloads the archive from S3 into a temp file, hands the path to
  `process_local/2`, and the parsed structure flows through to ClickHouse
  via `Tuist.Tests.create_test/1`.

  On xcresult-processor-mode pods (`TUIST_XCRESULT_PROCESSOR_MODE=true`)
  this runs as the Oban worker body. Those pods are macOS hosts (Scaleway
  Mac minis, external to the k8s cluster) because the parse path leans on
  `xcresulttool` which only ships with Xcode. Linux pods (web server,
  build-processor) drop the `:process_xcresult` queue from their Oban
  config when `TUIST_DELEGATE_PROCESS_XCRESULT=1` is set so jobs land
  exclusively on the macOS fleet. Self-hosted installs running on macOS
  consume the queue in-process like every other queue.
  """

  alias Tuist.Processor.XCResultNIF

  require Logger

  def process_local(archive_path, opts \\ []) do
    bucket = Keyword.get(opts, :s3_bucket) || Tuist.Environment.s3_bucket_name()
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

  defp process_archive(archive_path, temp_dir) do
    with :ok <- extract_archive(archive_path, temp_dir),
         xcresult_path when not is_nil(xcresult_path) <- find_xcresult(temp_dir) do
      root_dir = Path.dirname(xcresult_path)

      with {:ok, parsed_data} <- parse_xcresult(xcresult_path, root_dir) do
        quarantined_tests = read_quarantined_tests(xcresult_path)
        {:ok, apply_quarantine(parsed_data, quarantined_tests)}
      end
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
        XCResultNIF.decompress_archive(archive_path, temp_dir)

      {:error, reason} ->
        {:error, {:archive_read_failed, reason}}
    end
  end

  defp parse_xcresult(xcresult_path, root_dir) do
    :telemetry.span([:tuist, :processor, :xcresult, :parse], %{}, fn ->
      result = XCResultNIF.parse(xcresult_path, root_dir)
      status = if match?({:ok, _}, result), do: :ok, else: :error
      {result, %{status: status}}
    end)
  end

  defp read_quarantined_tests(xcresult_path) do
    json_path = Path.join(xcresult_path, "quarantined_tests.json")

    case File.read(json_path) do
      {:ok, content} -> JSON.decode!(content)
      {:error, :enoent} -> []
    end
  end

  defp apply_quarantine(parsed_data, []), do: parsed_data

  defp apply_quarantine(parsed_data, quarantined_tests) do
    test_modules =
      Enum.map(parsed_data["test_modules"] || [], fn module ->
        test_cases =
          Enum.map(module["test_cases"] || [], fn test_case ->
            is_quarantined =
              Enum.any?(quarantined_tests, fn q ->
                matches_quarantine?(test_case, module["name"], q)
              end)

            Map.put(test_case, "is_quarantined", is_quarantined)
          end)

        Map.put(module, "test_cases", test_cases)
      end)

    parsed_data
    |> Map.put("test_modules", test_modules)
    |> override_run_status_when_only_quarantined_failed()
  end

  # Mirror the local CLI behavior: when every failing test case is
  # quarantined (muted), the run passes from the user's perspective — CI
  # exits 0 — so the dashboard's run-level status should agree. Only the
  # top-level status is rewritten; individual test cases keep their raw
  # `failure` status so flakiness signal stays intact.
  defp override_run_status_when_only_quarantined_failed(%{"status" => "failure"} = data) do
    failing_cases =
      (data["test_modules"] || [])
      |> Enum.flat_map(&Map.get(&1, "test_cases", []))
      |> Enum.filter(&(&1["status"] == "failure"))

    if failing_cases != [] and Enum.all?(failing_cases, &Map.get(&1, "is_quarantined", false)) do
      Map.put(data, "status", "success")
    else
      data
    end
  end

  defp override_run_status_when_only_quarantined_failed(data), do: data

  defp matches_quarantine?(test_case, module_name, quarantined) do
    quarantined["target"] == module_name &&
      (is_nil(quarantined["class"]) || quarantined["class"] == test_case["test_suite_name"]) &&
      (is_nil(quarantined["method"]) || quarantined["method"] == test_case["name"])
  end

  defp upload_attachments(parsed_data, bucket, opts) do
    account_handle = Keyword.get(opts, :account_handle)
    project_handle = Keyword.get(opts, :project_handle)
    test_run_id = Keyword.get(opts, :test_run_id)

    if is_nil(account_handle) or is_nil(project_handle) or is_nil(test_run_id) do
      {:ok, parsed_data}
    else
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
            Logger.error("Attachment upload task crashed for #{original["file_name"]}: #{inspect(reason)}")

            acc
        end)

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
      Path.join(System.tmp_dir!(), "tuist_xcresult_processor_#{:erlang.unique_integer([:positive])}")

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
