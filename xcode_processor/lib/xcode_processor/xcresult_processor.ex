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
      upload_ctx = {bucket, account_handle, project_handle, test_run_id}

      test_modules =
        parsed_data
        |> Map.get("test_modules", [])
        |> Enum.map(&upload_test_case_attachments(&1, upload_ctx))

      {:ok, Map.put(parsed_data, "test_modules", test_modules)}
    end
  end

  defp upload_test_case_attachments(module, upload_ctx) do
    test_cases =
      module
      |> Map.get("test_cases", [])
      |> Enum.map(fn test_case ->
        attachments =
          test_case
          |> Map.get("attachments", [])
          |> Enum.map(&upload_attachment(&1, upload_ctx))

        Map.put(test_case, "attachments", attachments)
      end)

    Map.put(module, "test_cases", test_cases)
  end

  defp upload_attachment(attachment, {bucket, account_handle, project_handle, test_run_id}) do
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
