defmodule XcodeProcessor.XCResultProcessor do
  @moduledoc false

  require Logger

  def process(storage_key, opts \\ []) do
    bucket = XcodeProcessor.Environment.s3_bucket()
    temp_dir = make_temp_dir()
    zip_path = Path.join(temp_dir, "xcresult.zip")

    try do
      :telemetry.span([:xcode_processor, :xcresult], %{}, fn ->
        :telemetry.span([:xcode_processor, :s3, :download], %{}, fn ->
          {:ok, _} = ExAws.S3.download_file(bucket, storage_key, zip_path) |> ExAws.request()
          file_size = File.stat!(zip_path).size
          {:ok, %{file_size: file_size}}
        end)

        result = process_zip(zip_path, temp_dir)

        result =
          with {:ok, parsed_data} <- result do
            upload_attachments(parsed_data, bucket, opts)
          end

        status = if match?({:ok, _}, result), do: :ok, else: :error
        {result, %{status: status}}
      end)
    after
      cleanup_temp(temp_dir)
    end
  end

  defp process_zip(zip_path, temp_dir) do
    {:ok, _} = :zip.unzip(~c"#{zip_path}", [{:cwd, ~c"#{temp_dir}"}])

    case find_xcresult(temp_dir) do
      nil ->
        {:error, :xcresult_not_found}

      xcresult_path ->
        root_dir = Path.dirname(xcresult_path)
        parse_xcresult(xcresult_path, root_dir)
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
      # Collect all attachments with their location indices
      indexed_attachments = collect_indexed_attachments(Map.get(parsed_data, "test_modules", []))

      # Upload all attachments in parallel
      uploaded =
        indexed_attachments
        |> Task.async_stream(
          fn {mi, ci, ai, att} ->
            {mi, ci, ai,
             upload_attachment(att, bucket, account_handle, project_handle, test_run_id)}
          end,
          max_concurrency: 10,
          timeout: 60_000
        )
        |> Enum.map(fn {:ok, result} -> result end)

      test_modules = reassemble_attachments(Map.get(parsed_data, "test_modules", []), uploaded)
      {:ok, Map.put(parsed_data, "test_modules", test_modules)}
    end
  end

  defp collect_indexed_attachments(test_modules) do
    test_modules
    |> Enum.with_index()
    |> Enum.flat_map(fn {module, mi} ->
      module
      |> Map.get("test_cases", [])
      |> Enum.with_index()
      |> Enum.flat_map(&index_test_case_attachments(&1, mi))
    end)
  end

  defp index_test_case_attachments({test_case, ci}, mi) do
    test_case
    |> Map.get("attachments", [])
    |> Enum.with_index()
    |> Enum.map(fn {att, ai} -> {mi, ci, ai, att} end)
  end

  defp reassemble_attachments(test_modules, uploaded) do
    Enum.reduce(uploaded, test_modules, fn {mi, ci, ai, att}, modules ->
      List.update_at(modules, mi, fn module ->
        update_in(module, ["test_cases", Access.at(ci), "attachments", Access.at(ai)], fn _ ->
          att
        end)
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

      case ExAws.S3.put_object(bucket, s3_key, File.read!(file_path)) |> ExAws.request() do
        {:ok, _} ->
          attachment
          |> Map.delete("file_path")
          |> Map.put("attachment_id", attachment_id)

        {:error, reason} ->
          Logger.error("Failed to upload attachment #{file_name}: #{inspect(reason)}")
          attachment
      end
    else
      attachment
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
