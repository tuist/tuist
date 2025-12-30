defmodule Cache.S3Test do
  use ExUnit.Case, async: false
  use Mimic

  import ExUnit.CaptureLog

  alias Cache.S3
  alias ExAws.S3.Upload

  describe "presign_download_url/1" do
    test "returns presigned URL when bucket configured" do
      key = "acc/proj/cas/abc"

      expect(ExAws.Config, :new, fn :s3 -> %{dummy: true} end)

      expect(ExAws.S3, :presigned_url, fn _config, :get, "test-bucket", ^key, opts ->
        assert Keyword.get(opts, :expires_in) == 600
        {:ok, "https://example.com/#{key}?token=xyz"}
      end)

      assert {:ok, url} = S3.presign_download_url(key)
      assert url == "https://example.com/#{key}?token=xyz"
    end

    test "propagates error from presigned_url" do
      key = "acc/proj/cas/abc"

      expect(ExAws.Config, :new, fn :s3 -> %{dummy: true} end)

      expect(ExAws.S3, :presigned_url, fn _config, :get, "test-bucket", ^key, _opts ->
        {:error, :boom}
      end)

      assert {:error, :boom} = S3.presign_download_url(key)
    end
  end

  describe "remote_accel_path/1" do
    test "builds internal remote path for https URL with query" do
      url = "https://example.com/prefix/acc/proj/cas/abc?token=xyz"
      assert S3.remote_accel_path(url) == "/internal/remote/https/example.com/prefix/acc/proj/cas/abc?token=xyz"
    end

    test "forces https scheme regardless of input" do
      assert S3.remote_accel_path("http://example.com/foo") == "/internal/remote/https/example.com/foo"
      assert S3.remote_accel_path("https://example.com/bar") == "/internal/remote/https/example.com/bar"
    end

    test "ensures path slash when path missing" do
      url = "https://example.com"
      assert S3.remote_accel_path(url) == "/internal/remote/https/example.com/"
    end
  end

  describe "exists?/1" do
    test "returns true when file exists in S3" do
      key = "acc/proj/cas/abc"

      expect(ExAws.S3, :head_object, fn "test-bucket", ^key ->
        %ExAws.Operation.S3{
          bucket: "test-bucket",
          path: key
        }
      end)

      expect(ExAws, :request, fn _head_object, _opts -> {:ok, %{status_code: 200}} end)

      assert S3.exists?(key) == true
    end

    test "returns false when file does not exist in S3 (404)" do
      key = "acc/proj/cas/nonexistent"

      expect(ExAws.S3, :head_object, fn "test-bucket", ^key ->
        %ExAws.Operation.S3{
          bucket: "test-bucket",
          path: key
        }
      end)

      expect(ExAws, :request, fn _head_object, _opts -> {:error, {:http_error, 404, "Not Found"}} end)

      assert S3.exists?(key) == false
    end

    test "returns false when S3 request fails" do
      key = "acc/proj/cas/error"

      expect(ExAws.S3, :head_object, fn "test-bucket", ^key ->
        %ExAws.Operation.S3{
          bucket: "test-bucket",
          path: key
        }
      end)

      expect(ExAws, :request, fn _head_object, _opts -> {:error, :timeout} end)

      assert S3.exists?(key) == false
    end
  end

  describe "upload/1" do
    test "uploads file to S3 when local file exists" do
      key = "test_account/test_project/cas/TE/ST/test_hash"
      {:ok, tmp_dir} = Briefly.create(directory: true)
      local_path = Path.join(tmp_dir, "test_hash")

      File.write!(local_path, "test content")

      expect(Cache.Disk, :artifact_path, fn ^key -> local_path end)

      expect(Upload, :stream_file, fn ^local_path -> {:stream, local_path} end)

      expect(ExAws.S3, :upload, fn {:stream, ^local_path}, "test-bucket", ^key ->
        {:upload_operation, "test-bucket", key}
      end)

      expect(ExAws, :request, fn {:upload_operation, "test-bucket", ^key} ->
        {:ok, %{status_code: 200}}
      end)

      capture_log(fn ->
        assert :ok = S3.upload(key)
      end)
    end

    test "returns :ok when local file does not exist" do
      key = "test_account/test_project/cas/TE/ST/test_hash"

      expect(Cache.Disk, :artifact_path, fn ^key -> "/nonexistent/path/file" end)

      capture_log(fn ->
        assert :ok = S3.upload(key)
      end)
    end

    test "returns error on S3 failure" do
      key = "test_account/test_project/cas/TE/ST/test_hash"
      {:ok, tmp_dir} = Briefly.create(directory: true)
      local_path = Path.join(tmp_dir, "test_hash")

      File.write!(local_path, "test content")

      expect(Cache.Disk, :artifact_path, fn ^key -> local_path end)

      expect(Upload, :stream_file, fn ^local_path -> {:stream, local_path} end)

      expect(ExAws.S3, :upload, fn {:stream, ^local_path}, "test-bucket", ^key ->
        {:upload_operation, "test-bucket", key}
      end)

      expect(ExAws, :request, fn {:upload_operation, "test-bucket", ^key} ->
        {:error, :timeout}
      end)

      capture_log(fn ->
        assert {:error, :timeout} = S3.upload(key)
      end)
    end

    test "returns :rate_limited error on 429 response" do
      key = "test_account/test_project/cas/TE/ST/test_hash"
      {:ok, tmp_dir} = Briefly.create(directory: true)
      local_path = Path.join(tmp_dir, "test_hash")

      File.write!(local_path, "test content")

      expect(Cache.Disk, :artifact_path, fn ^key -> local_path end)

      expect(Upload, :stream_file, fn ^local_path -> {:stream, local_path} end)

      expect(ExAws.S3, :upload, fn {:stream, ^local_path}, "test-bucket", ^key ->
        {:upload_operation, "test-bucket", key}
      end)

      expect(ExAws, :request, fn {:upload_operation, "test-bucket", ^key} ->
        {:error, {:http_error, 429, %{body: "Too many requests"}}}
      end)

      capture_log(fn ->
        assert {:error, :rate_limited} = S3.upload(key)
      end)
    end
  end

  describe "download/1" do
    test "downloads file from S3 when it exists" do
      key = "test_account/test_project/cas/TE/ST/test_hash"
      {:ok, tmp_dir} = Briefly.create(directory: true)
      local_path = Path.join(tmp_dir, "test_hash")

      expect(ExAws.S3, :head_object, fn "test-bucket", ^key ->
        %ExAws.Operation.S3{bucket: "test-bucket", path: key}
      end)

      expect(ExAws, :request, fn %ExAws.Operation.S3{} -> {:ok, %{status_code: 200}} end)

      expect(Cache.Disk, :artifact_path, fn ^key -> local_path end)

      expect(ExAws.S3, :download_file, fn "test-bucket", ^key, ^local_path ->
        {:download_operation, "test-bucket", key, local_path}
      end)

      expect(ExAws, :request, fn {:download_operation, "test-bucket", ^key, ^local_path} ->
        File.write!(local_path, "downloaded content")
        {:ok, :done}
      end)

      capture_log(fn ->
        assert {:ok, :hit} = S3.download(key)
      end)
    end

    test "returns {:ok, :miss} when file does not exist in S3" do
      key = "test_account/test_project/cas/TE/ST/test_hash"

      expect(ExAws.S3, :head_object, fn "test-bucket", ^key ->
        %ExAws.Operation.S3{bucket: "test-bucket", path: key}
      end)

      expect(ExAws, :request, fn %ExAws.Operation.S3{} -> {:error, {:http_error, 404, "Not Found"}} end)

      capture_log(fn ->
        assert {:ok, :miss} = S3.download(key)
      end)
    end

    test "returns error on S3 download failure" do
      key = "test_account/test_project/cas/TE/ST/test_hash"
      {:ok, tmp_dir} = Briefly.create(directory: true)
      local_path = Path.join(tmp_dir, "test_hash")

      expect(ExAws.S3, :head_object, fn "test-bucket", ^key ->
        %ExAws.Operation.S3{bucket: "test-bucket", path: key}
      end)

      expect(ExAws, :request, fn %ExAws.Operation.S3{} -> {:ok, %{status_code: 200}} end)

      expect(Cache.Disk, :artifact_path, fn ^key -> local_path end)

      expect(ExAws.S3, :download_file, fn "test-bucket", ^key, ^local_path ->
        {:download_operation, "test-bucket", key, local_path}
      end)

      expect(ExAws, :request, fn {:download_operation, "test-bucket", ^key, ^local_path} ->
        {:error, :timeout}
      end)

      capture_log(fn ->
        assert {:error, :timeout} = S3.download(key)
      end)
    end

    test "returns :rate_limited error on 429 during exists check" do
      key = "test_account/test_project/cas/TE/ST/test_hash"

      expect(ExAws.S3, :head_object, fn "test-bucket", ^key ->
        %ExAws.Operation.S3{bucket: "test-bucket", path: key}
      end)

      expect(ExAws, :request, fn %ExAws.Operation.S3{} ->
        {:error, {:http_error, 429, %{body: "Too many requests"}}}
      end)

      capture_log(fn ->
        assert {:error, :rate_limited} = S3.download(key)
      end)
    end

    test "returns :rate_limited error on 429 during download" do
      key = "test_account/test_project/cas/TE/ST/test_hash"
      {:ok, tmp_dir} = Briefly.create(directory: true)
      local_path = Path.join(tmp_dir, "test_hash")

      expect(ExAws.S3, :head_object, fn "test-bucket", ^key ->
        %ExAws.Operation.S3{bucket: "test-bucket", path: key}
      end)

      expect(ExAws, :request, fn %ExAws.Operation.S3{} -> {:ok, %{status_code: 200}} end)

      expect(Cache.Disk, :artifact_path, fn ^key -> local_path end)

      expect(ExAws.S3, :download_file, fn "test-bucket", ^key, ^local_path ->
        {:download_operation, "test-bucket", key, local_path}
      end)

      expect(ExAws, :request, fn {:download_operation, "test-bucket", ^key, ^local_path} ->
        {:error, {:http_error, 429, %{body: "Too many requests"}}}
      end)

      capture_log(fn ->
        assert {:error, :rate_limited} = S3.download(key)
      end)
    end
  end
end
