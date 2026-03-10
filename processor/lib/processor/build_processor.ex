defmodule Processor.BuildProcessor do
  @moduledoc false

  def process(storage_key, xcode_cache_upload_enabled) do
    bucket = Application.get_env(:processor, :s3_bucket, "tuist")
    temp_dir = make_temp_dir()
    build_path = Path.join(temp_dir, "build.zip")

    try do
      {:ok, _} = ExAws.S3.download_file(bucket, storage_key, build_path) |> ExAws.request()
      process_zip(build_path, temp_dir, xcode_cache_upload_enabled)
    after
      cleanup_temp(temp_dir)
    end
  end

  def process_build(build_zip_path, xcode_cache_upload_enabled) do
    temp_dir = make_temp_dir()

    try do
      process_zip(build_zip_path, temp_dir, xcode_cache_upload_enabled)
    after
      cleanup_temp(temp_dir)
    end
  end

  defp process_zip(zip_path, temp_dir, xcode_cache_upload_enabled) do
    {:ok, _} = :zip.unzip(~c"#{zip_path}", [{:cwd, ~c"#{temp_dir}"}])
    xcactivitylog_path = find_xcactivitylog(temp_dir)
    cas_path = Path.join(temp_dir, "cas_metadata")

    {:ok, parsed_data} = Processor.XCActivityLogNIF.parse(xcactivitylog_path, cas_path, xcode_cache_upload_enabled)
    {:ok, parsed_data}
  end

  defp make_temp_dir do
    temp_dir = Path.join(System.tmp_dir!(), "processor_#{:erlang.unique_integer([:positive])}")
    File.mkdir_p!(temp_dir)
    temp_dir
  end

  defp find_xcactivitylog(temp_dir) do
    xcactivitylog_dir = Path.join(temp_dir, "build/xcactivitylog")

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
