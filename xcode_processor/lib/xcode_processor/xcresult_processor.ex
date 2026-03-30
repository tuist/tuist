defmodule XcodeProcessor.XCResultProcessor do
  @moduledoc false

  def process(storage_key) do
    bucket = Application.get_env(:xcode_processor, :s3_bucket, "tuist")
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
