defmodule Cache.MultipartUploadsTest do
  use ExUnit.Case, async: false

  alias Cache.MultipartUploads

  setup do
    :ok
  end

  describe "start_upload/5" do
    test "creates upload and returns UUID" do
      {:ok, upload_id} = MultipartUploads.start_upload("acc", "proj", "builds", "abc123", "test.zip")
      assert is_binary(upload_id)
      assert String.length(upload_id) == 36
    end

    test "stores upload metadata" do
      {:ok, upload_id} = MultipartUploads.start_upload("acc", "proj", "builds", "abc123", "test.zip")
      {:ok, upload} = MultipartUploads.get_upload(upload_id)

      assert upload.account_handle == "acc"
      assert upload.project_handle == "proj"
      assert upload.category == "builds"
      assert upload.hash == "abc123"
      assert upload.name == "test.zip"
      assert upload.parts == %{}
      assert upload.total_bytes == 0
    end
  end

  describe "add_part/4" do
    test "records part for valid upload" do
      {:ok, upload_id} = MultipartUploads.start_upload("acc", "proj", "builds", "abc123", "test.zip")

      tmp_path = Path.join(System.tmp_dir!(), "test-part-#{:erlang.unique_integer([:positive])}")
      File.write!(tmp_path, String.duplicate("x", 1000))

      assert :ok = MultipartUploads.add_part(upload_id, 1, tmp_path, 1000)

      {:ok, upload} = MultipartUploads.get_upload(upload_id)
      assert Map.has_key?(upload.parts, 1)
      assert upload.parts[1].path == tmp_path
      assert upload.parts[1].size == 1000
      assert upload.total_bytes == 1000

      File.rm(tmp_path)
    end

    test "returns error for unknown upload" do
      assert {:error, :upload_not_found} = MultipartUploads.add_part("nonexistent", 1, "/tmp/foo", 100)
    end

    test "returns error when part exceeds 10MB" do
      {:ok, upload_id} = MultipartUploads.start_upload("acc", "proj", "builds", "abc123", "test.zip")
      size = 11 * 1024 * 1024

      assert {:error, :part_too_large} = MultipartUploads.add_part(upload_id, 1, "/tmp/foo", size)
    end

    test "returns error when total exceeds 500MB" do
      {:ok, upload_id} = MultipartUploads.start_upload("acc", "proj", "builds", "abc123", "test.zip")

      part_size = 10 * 1024 * 1024

      for i <- 1..50 do
        MultipartUploads.add_part(upload_id, i, "/tmp/part#{i}", part_size)
      end

      assert {:error, :total_size_exceeded} = MultipartUploads.add_part(upload_id, 51, "/tmp/part51", part_size)
    end

    test "can add multiple parts" do
      {:ok, upload_id} = MultipartUploads.start_upload("acc", "proj", "builds", "abc123", "test.zip")

      assert :ok = MultipartUploads.add_part(upload_id, 1, "/tmp/part1", 1000)
      assert :ok = MultipartUploads.add_part(upload_id, 2, "/tmp/part2", 2000)
      assert :ok = MultipartUploads.add_part(upload_id, 3, "/tmp/part3", 3000)

      {:ok, upload} = MultipartUploads.get_upload(upload_id)
      assert map_size(upload.parts) == 3
      assert upload.total_bytes == 6000
    end
  end

  describe "get_upload/1" do
    test "returns upload data for valid upload" do
      {:ok, upload_id} = MultipartUploads.start_upload("acc", "proj", "builds", "abc123", "test.zip")
      {:ok, upload} = MultipartUploads.get_upload(upload_id)

      assert upload.account_handle == "acc"
    end

    test "returns error for unknown upload" do
      assert {:error, :not_found} = MultipartUploads.get_upload("nonexistent")
    end
  end

  describe "complete_upload/1" do
    test "returns upload data and removes from state" do
      {:ok, upload_id} = MultipartUploads.start_upload("acc", "proj", "builds", "abc123", "test.zip")

      tmp_path = Path.join(System.tmp_dir!(), "test-part-#{:erlang.unique_integer([:positive])}")
      File.write!(tmp_path, "data")
      MultipartUploads.add_part(upload_id, 1, tmp_path, 4)

      {:ok, upload} = MultipartUploads.complete_upload(upload_id)

      assert upload.account_handle == "acc"
      assert upload.project_handle == "proj"
      assert Map.has_key?(upload.parts, 1)

      assert {:error, :not_found} = MultipartUploads.get_upload(upload_id)

      File.rm(tmp_path)
    end

    test "returns error for unknown upload" do
      assert {:error, :not_found} = MultipartUploads.complete_upload("nonexistent")
    end
  end

  describe "abort_upload/1" do
    test "removes upload and cleans up temp files" do
      {:ok, upload_id} = MultipartUploads.start_upload("acc", "proj", "builds", "abc123", "test.zip")

      tmp_path = Path.join(System.tmp_dir!(), "test-part-#{:erlang.unique_integer([:positive])}")
      File.write!(tmp_path, "data")
      MultipartUploads.add_part(upload_id, 1, tmp_path, 4)

      assert :ok = MultipartUploads.abort_upload(upload_id)
      assert {:error, :not_found} = MultipartUploads.get_upload(upload_id)
      refute File.exists?(tmp_path)
    end

    test "returns ok for unknown upload" do
      assert :ok = MultipartUploads.abort_upload("nonexistent")
    end
  end
end
