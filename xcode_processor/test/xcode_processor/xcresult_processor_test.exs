defmodule XcodeProcessor.XCResultProcessorTest do
  use ExUnit.Case, async: true
  use Mimic

  alias XcodeProcessor.XCResultProcessor

  setup :verify_on_exit!

  defp create_xcresult_zip do
    temp_dir =
      Path.join(
        System.tmp_dir!(),
        "xcresult_test_fixture_#{:erlang.unique_integer([:positive])}"
      )

    File.mkdir_p!(temp_dir)

    zip_path = Path.join(temp_dir, "fixture.zip")

    {:ok, _} =
      :zip.create(
        ~c"#{zip_path}",
        [{~c"Test.xcresult/Info.plist", "fake-plist-content"}]
      )

    {temp_dir, zip_path}
  end

  describe "process/1" do
    test "returns parsed data on successful processing" do
      {fixture_dir, fixture_zip} = create_xcresult_zip()
      on_exit(fn -> File.rm_rf(fixture_dir) end)

      parsed_data = %{"tests" => [%{"name" => "testExample", "status" => "passed"}]}

      stub(ExAws.S3, :download_file, fn _bucket, _key, dest_path ->
        File.cp!(fixture_zip, dest_path)
        %ExAws.Operation.S3{http_method: :get, bucket: "tuist", path: "key"}
      end)

      expect(ExAws, :request, fn _ -> {:ok, :done} end)

      expect(XcodeProcessor.XCResultNIF, :parse, fn xcresult_path, _root_dir ->
        assert String.ends_with?(xcresult_path, "Test.xcresult")
        {:ok, parsed_data}
      end)

      assert {:ok, ^parsed_data} = XCResultProcessor.process("some/key.zip")
    end

    test "returns error when S3 download fails" do
      stub(ExAws.S3, :download_file, fn _bucket, _key, _dest_path ->
        %ExAws.Operation.S3{http_method: :get, bucket: "tuist", path: "key"}
      end)

      expect(ExAws, :request, fn _ -> {:error, {:http_error, 404, "not found"}} end)

      assert {:error, {:http_error, 404, "not found"}} =
               XCResultProcessor.process("some/key.zip")
    end

    test "returns error when NIF parse fails" do
      {fixture_dir, fixture_zip} = create_xcresult_zip()
      on_exit(fn -> File.rm_rf(fixture_dir) end)

      stub(ExAws.S3, :download_file, fn _bucket, _key, dest_path ->
        File.cp!(fixture_zip, dest_path)
        %ExAws.Operation.S3{http_method: :get, bucket: "tuist", path: "key"}
      end)

      expect(ExAws, :request, fn _ -> {:ok, :done} end)

      expect(XcodeProcessor.XCResultNIF, :parse, fn _xcresult_path, _root_dir ->
        {:error, "parse failed"}
      end)

      assert {:error, "parse failed"} = XCResultProcessor.process("some/key.zip")
    end

    @tag :tmp_dir
    test "applies quarantine marking from quarantined_tests.json", %{tmp_dir: tmp_dir} do
      quarantined_tests = [
        %{"target" => "AppTests", "class" => "Suite", "method" => "testA()"}
      ]

      quarantine_json = JSON.encode!(quarantined_tests)

      {:ok, fixture_zip} =
        :zip.create(
          ~c"#{Path.join(tmp_dir, "fixture.zip")}",
          [
            {~c"Test.xcresult/Info.plist", "fake"},
            {~c"Test.xcresult/quarantined_tests.json", quarantine_json}
          ]
        )

      parsed_data = %{
        "test_modules" => [
          %{
            "name" => "AppTests",
            "test_cases" => [
              %{"name" => "testA()", "test_suite_name" => "Suite", "status" => "failed"},
              %{"name" => "testB()", "test_suite_name" => "Suite", "status" => "passed"}
            ]
          }
        ]
      }

      stub(ExAws.S3, :download_file, fn _bucket, _key, dest_path ->
        File.cp!(to_string(fixture_zip), dest_path)
        %ExAws.Operation.S3{http_method: :get, bucket: "tuist", path: "key"}
      end)

      expect(ExAws, :request, fn _ -> {:ok, :done} end)

      expect(XcodeProcessor.XCResultNIF, :parse, fn _path, _root ->
        {:ok, parsed_data}
      end)

      {:ok, result} = XCResultProcessor.process("some/key.zip")
      [module] = result["test_modules"]
      [case_a, case_b] = module["test_cases"]

      assert case_a["is_quarantined"] == true
      assert case_b["is_quarantined"] == false
    end

    test "returns parsed data unchanged when no quarantined_tests.json" do
      {fixture_dir, fixture_zip} = create_xcresult_zip()
      on_exit(fn -> File.rm_rf(fixture_dir) end)

      parsed_data = %{
        "test_modules" => [
          %{
            "name" => "AppTests",
            "test_cases" => [
              %{"name" => "testA()", "test_suite_name" => "Suite", "status" => "passed"}
            ]
          }
        ]
      }

      stub(ExAws.S3, :download_file, fn _bucket, _key, dest_path ->
        File.cp!(fixture_zip, dest_path)
        %ExAws.Operation.S3{http_method: :get, bucket: "tuist", path: "key"}
      end)

      expect(ExAws, :request, fn _ -> {:ok, :done} end)

      expect(XcodeProcessor.XCResultNIF, :parse, fn _path, _root ->
        {:ok, parsed_data}
      end)

      {:ok, result} = XCResultProcessor.process("some/key.zip")
      [module] = result["test_modules"]
      [case_a] = module["test_cases"]

      refute Map.has_key?(case_a, "is_quarantined")
    end

    test "uploads attachments to S3 when handles are provided" do
      {fixture_dir, fixture_zip} = create_xcresult_zip()
      on_exit(fn -> File.rm_rf(fixture_dir) end)

      attachment_file = Path.join(fixture_dir, "screenshot.png")
      File.write!(attachment_file, "fake-png-data")

      parsed_data = %{
        "test_modules" => [
          %{
            "name" => "Module",
            "test_cases" => [
              %{
                "name" => "test_example",
                "attachments" => [
                  %{
                    "file_path" => attachment_file,
                    "file_name" => "screenshot.png",
                    "repetition_number" => nil
                  }
                ]
              }
            ]
          }
        ]
      }

      # Download call
      expect(ExAws, :request, fn %ExAws.Operation.S3{http_method: :get} -> {:ok, :done} end)

      # Upload call for the attachment (streaming multipart upload)
      expect(ExAws, :request, fn %ExAws.S3.Upload{bucket: _bucket, path: path} ->
        assert String.contains?(path, "tests/runs/run-123/attachments/")
        assert String.ends_with?(path, "/screenshot.png")
        {:ok, %{status_code: 200}}
      end)

      stub(ExAws.S3, :download_file, fn _bucket, _key, dest_path ->
        File.cp!(fixture_zip, dest_path)
        %ExAws.Operation.S3{http_method: :get, bucket: "tuist", path: "key"}
      end)

      stub(ExAws.S3, :upload, fn stream, _bucket, key ->
        %ExAws.S3.Upload{bucket: "tuist", path: key, src: stream}
      end)

      expect(XcodeProcessor.XCResultNIF, :parse, fn _path, _root ->
        {:ok, parsed_data}
      end)

      opts = [
        test_run_id: "run-123",
        account_handle: "MyOrg",
        project_handle: "MyProject"
      ]

      assert {:ok, result} = XCResultProcessor.process("some/key.zip", opts)

      [module] = result["test_modules"]
      [test_case] = module["test_cases"]
      [attachment] = test_case["attachments"]
      assert attachment["attachment_id"]
      assert attachment["file_name"] == "screenshot.png"
      refute Map.has_key?(attachment, "file_path")
    end

    test "dispatches to AppleArchive NIF when the downloaded payload is not PKZIP" do
      # AppleArchive LZFSE-compressed streams start with the "bvx" prefix; any
      # non-PKZIP header routes through `XCResultNIF.decompress_archive`.
      fixture_dir =
        Path.join(System.tmp_dir!(), "xcresult_aar_fixture_#{:erlang.unique_integer([:positive])}")

      File.mkdir_p!(fixture_dir)
      fixture_path = Path.join(fixture_dir, "fixture.aar")
      File.write!(fixture_path, <<0x62, 0x76, 0x78, 0x32, "fake-aar-body">>)
      on_exit(fn -> File.rm_rf(fixture_dir) end)

      parsed_data = %{"tests" => [%{"name" => "testAar", "status" => "passed"}]}

      stub(ExAws.S3, :download_file, fn _bucket, _key, dest_path ->
        File.cp!(fixture_path, dest_path)
        %ExAws.Operation.S3{http_method: :get, bucket: "tuist", path: "key"}
      end)

      expect(ExAws, :request, fn _ -> {:ok, :done} end)

      expect(XcodeProcessor.XCResultNIF, :decompress_archive, fn _archive_path, temp_dir ->
        File.mkdir_p!(Path.join(temp_dir, "Test.xcresult"))
        File.write!(Path.join([temp_dir, "Test.xcresult", "Info.plist"]), "fake-plist")
        :ok
      end)

      expect(XcodeProcessor.XCResultNIF, :parse, fn xcresult_path, _root ->
        assert String.ends_with?(xcresult_path, "Test.xcresult")
        {:ok, parsed_data}
      end)

      assert {:ok, ^parsed_data} = XCResultProcessor.process("some/key.aar")
    end

    test "surfaces NIF decompression failures for AppleArchive payloads" do
      fixture_dir =
        Path.join(System.tmp_dir!(), "xcresult_aar_failure_#{:erlang.unique_integer([:positive])}")

      File.mkdir_p!(fixture_dir)
      fixture_path = Path.join(fixture_dir, "fixture.aar")
      File.write!(fixture_path, <<0x62, 0x76, 0x78, 0x32, "fake-aar-body">>)
      on_exit(fn -> File.rm_rf(fixture_dir) end)

      stub(ExAws.S3, :download_file, fn _bucket, _key, dest_path ->
        File.cp!(fixture_path, dest_path)
        %ExAws.Operation.S3{http_method: :get, bucket: "tuist", path: "key"}
      end)

      expect(ExAws, :request, fn _ -> {:ok, :done} end)

      expect(XcodeProcessor.XCResultNIF, :decompress_archive, fn _archive_path, _temp_dir ->
        {:error, "decompression failed"}
      end)

      assert {:error, "decompression failed"} = XCResultProcessor.process("some/key.aar")
    end

    test "cleans up temp directory even when processing fails" do
      stub(ExAws.S3, :download_file, fn _bucket, _key, _dest_path ->
        %ExAws.Operation.S3{http_method: :get, bucket: "tuist", path: "key"}
      end)

      expect(ExAws, :request, fn _ -> {:error, {:http_error, 500, "server error"}} end)

      temp_dirs_before =
        Path.join(System.tmp_dir!(), "xcode_processor_*")
        |> Path.wildcard()

      assert {:error, {:http_error, 500, "server error"}} =
               XCResultProcessor.process("some/key.zip")

      temp_dirs_after =
        Path.join(System.tmp_dir!(), "xcode_processor_*")
        |> Path.wildcard()

      new_dirs = temp_dirs_after -- temp_dirs_before
      assert new_dirs == []
    end
  end
end
