defmodule Processor.BuildProcessorTest do
  use ExUnit.Case, async: true
  use Mimic

  alias Processor.BuildProcessor

  setup :verify_on_exit!

  describe "process/2" do
    test "downloads from S3 and processes the build" do
      storage_key = "builds/test-build.zip"
      build_bytes = build_test_zip()

      expect(ExAws.S3, :get_object, fn "tuist", ^storage_key ->
        %ExAws.Operation.S3{}
      end)

      expect(ExAws, :request, fn _ ->
        {:ok, %{body: build_bytes}}
      end)

      expect(Processor.XCActivityLogNIF, :parse, fn path, cas_path, true ->
        assert String.ends_with?(path, "test.xcactivitylog")
        assert String.ends_with?(cas_path, "cas_metadata")
        {:ok, %{"duration" => 1000, "status" => "success"}}
      end)

      assert {:ok, %{"duration" => 1000, "status" => "success"}} =
               BuildProcessor.process(storage_key, true)
    end
  end

  describe "process_build/2" do
    test "extracts build and parses xcactivitylog" do
      build_bytes = build_test_zip()

      expect(Processor.XCActivityLogNIF, :parse, fn path, cas_path, true ->
        assert String.ends_with?(path, "test.xcactivitylog")
        assert String.ends_with?(cas_path, "cas_metadata")
        {:ok, %{"duration" => 500, "status" => "success", "targets" => []}}
      end)

      assert {:ok, %{"duration" => 500, "status" => "success", "targets" => []}} =
               BuildProcessor.process_build(build_bytes, true)
    end

    test "passes xcode_cache_upload_enabled to NIF" do
      build_bytes = build_test_zip()

      expect(Processor.XCActivityLogNIF, :parse, fn _path, _cas_path, false ->
        {:ok, %{"status" => "success"}}
      end)

      assert {:ok, _} = BuildProcessor.process_build(build_bytes, false)
    end

    test "ignores manifest when present" do
      build_bytes = build_test_zip(manifest: %{"xcode_cache_upload_enabled" => true})

      expect(Processor.XCActivityLogNIF, :parse, fn _path, _cas_path, true ->
        {:ok, %{"status" => "success"}}
      end)

      assert {:ok, _} = BuildProcessor.process_build(build_bytes, true)
    end

    test "raises when xcactivitylog directory is missing" do
      build_bytes = build_test_zip(include_xcactivitylog: false)

      assert_raise MatchError, fn ->
        BuildProcessor.process_build(build_bytes, true)
      end
    end

    test "raises when NIF parsing fails" do
      build_bytes = build_test_zip()

      expect(Processor.XCActivityLogNIF, :parse, fn _path, _cas_path, true ->
        {:error, "parse_failed"}
      end)

      assert_raise MatchError, fn ->
        BuildProcessor.process_build(build_bytes, true)
      end
    end

    test "raises for invalid zip data" do
      assert_raise MatchError, fn ->
        BuildProcessor.process_build("not a zip file", true)
      end
    end
  end

  defp build_test_zip(opts \\ []) do
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

    {:ok, {_filename, zip_bytes}} = :zip.create(~c"build.zip", files, [:memory])
    zip_bytes
  end
end
