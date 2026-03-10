defmodule Processor.BuildProcessor do
  @moduledoc false

  def process(storage_key, xcode_cache_upload_enabled) do
    bucket = Application.get_env(:processor, :s3_bucket, "tuist")

    {:ok, %{body: body}} = ExAws.S3.get_object(bucket, storage_key) |> ExAws.request()

    process_build(body, xcode_cache_upload_enabled)
  end

  def process_build(build_bytes, xcode_cache_upload_enabled) do
    temp_dir = extract_build(build_bytes)

    try do
      xcactivitylog_path = find_xcactivitylog(temp_dir)
      cas_path = Path.join(temp_dir, "cas_metadata")

      {:ok, parsed_data} = Processor.XCActivityLogNIF.parse(xcactivitylog_path, cas_path, xcode_cache_upload_enabled)
      {:ok, parsed_data}
    after
      cleanup_temp(temp_dir)
    end
  end

  defp extract_build(build_bytes) do
    temp_dir = Path.join(System.tmp_dir!(), "processor_#{:erlang.unique_integer([:positive])}")
    File.mkdir_p!(temp_dir)
    build_path = Path.join(temp_dir, "build.zip")
    File.write!(build_path, build_bytes)

    {:ok, _} = :zip.unzip(~c"#{build_path}", [{:cwd, ~c"#{temp_dir}"}])
    temp_dir
  end

  defp find_xcactivitylog(temp_dir) do
    xcactivitylog_dir = Path.join(temp_dir, "build_archive/xcactivitylog")

    {:ok, files} = File.ls(xcactivitylog_dir)
    file = Enum.find(files, &String.ends_with?(&1, ".xcactivitylog"))
    Path.join(xcactivitylog_dir, file)
  end

  defp cleanup_temp(nil), do: :ok

  defp cleanup_temp(temp_dir) do
    File.rm_rf(temp_dir)
    :ok
  end
end
