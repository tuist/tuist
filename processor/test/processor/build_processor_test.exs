defmodule Processor.BuildProcessorTest do
  use ExUnit.Case, async: true
  use Mimic

  alias Processor.BuildProcessor

  setup :verify_on_exit!

  describe "process/1" do
    test "downloads from S3 and processes the archive" do
      storage_key = "builds/test-archive.zip"
      archive_bytes = build_test_archive()

      expect(ExAws.S3, :get_object, fn "tuist", ^storage_key ->
        %ExAws.Operation.S3{}
      end)

      expect(ExAws, :request, fn _ ->
        {:ok, %{body: archive_bytes}}
      end)

      expect(Processor.XCActivityLogNIF, :parse, fn path, cas_path, true ->
        assert String.ends_with?(path, "test.xcactivitylog")
        assert String.ends_with?(cas_path, "cas_metadata")
        {:ok, %{"duration" => 1000, "status" => "success"}}
      end)

      assert {:ok, %{"duration" => 1000, "status" => "success"}} =
               BuildProcessor.process(storage_key)
    end

  end

  describe "process_build/1" do
    test "extracts archive and parses xcactivitylog" do
      archive_bytes = build_test_archive()

      expect(Processor.XCActivityLogNIF, :parse, fn path, cas_path, true ->
        assert String.ends_with?(path, "test.xcactivitylog")
        assert String.ends_with?(cas_path, "cas_metadata")
        {:ok, %{"duration" => 500, "status" => "success", "targets" => []}}
      end)

      assert {:ok, %{"duration" => 500, "status" => "success", "targets" => []}} =
               BuildProcessor.process_build(archive_bytes)
    end

    test "ignores manifest when present" do
      archive_bytes = build_test_archive(manifest: %{"cache_upload_enabled" => true})

      expect(Processor.XCActivityLogNIF, :parse, fn _path, _cas_path, true ->
        {:ok, %{"status" => "success"}}
      end)

      assert {:ok, _} = BuildProcessor.process_build(archive_bytes)
    end

    test "returns error when xcactivitylog directory is missing" do
      archive_bytes = build_test_archive(include_xcactivitylog: false)

      assert {:error, :xcactivitylog_dir_not_found} =
               BuildProcessor.process_build(archive_bytes)
    end

    test "returns error when NIF parsing fails" do
      archive_bytes = build_test_archive()

      expect(Processor.XCActivityLogNIF, :parse, fn _path, _cas_path, true ->
        {:error, "parse_failed"}
      end)

      assert {:error, {:parse_failed, "parse_failed"}} =
               BuildProcessor.process_build(archive_bytes)
    end

    test "returns error for invalid zip data" do
      assert {:error, {:unzip_failed, _}} =
               BuildProcessor.process_build("not a zip file")
    end
  end

  defp build_test_archive(opts \\ []) do
    include_xcactivitylog = Keyword.get(opts, :include_xcactivitylog, true)
    manifest = Keyword.get(opts, :manifest, nil)

    files =
      if include_xcactivitylog do
        [{~c"build_archive/xcactivitylog/test.xcactivitylog", "fake log data"}]
      else
        [{~c"build_archive/other_file.txt", "some data"}]
      end

    files =
      if manifest do
        [{~c"build_archive/manifest.json", Jason.encode!(manifest)} | files]
      else
        files
      end

    {:ok, {_filename, zip_bytes}} = :zip.create(~c"archive.zip", files, [:memory])
    zip_bytes
  end
end
