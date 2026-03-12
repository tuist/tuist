defmodule Cache.S3Test do
  use ExUnit.Case, async: true
  use Mimic

  import ExUnit.CaptureLog

  alias Cache.S3
  alias ExAws.S3.Upload

  setup :set_mimic_from_context

  describe "etag_from_headers/1" do
    test "extracts etag from lowercase header key" do
      headers = %{"etag" => "\"abc123\""}
      assert S3.etag_from_headers(headers) == "abc123"
    end

    test "extracts etag from uppercase header key" do
      headers = %{"ETag" => "\"def456\""}
      assert S3.etag_from_headers(headers) == "def456"
    end

    test "prefers lowercase etag key over uppercase" do
      headers = %{"etag" => "\"lowercase\"", "ETag" => "\"uppercase\""}
      assert S3.etag_from_headers(headers) == "lowercase"
    end

    test "returns nil when no etag header present" do
      assert S3.etag_from_headers(%{}) == nil
    end

    test "unwraps list values" do
      headers = %{"etag" => ["\"list-value\"", "\"other\""]}
      assert S3.etag_from_headers(headers) == "list-value"
    end

    test "strips whitespace and quotes" do
      headers = %{"etag" => "  \"spaced\"  "}
      assert S3.etag_from_headers(headers) == "spaced"
    end

    test "handles unquoted etag values" do
      headers = %{"etag" => "no-quotes"}
      assert S3.etag_from_headers(headers) == "no-quotes"
    end
  end

  describe "presign_download_url/1" do
    test "returns presigned URL for cache type" do
      key = "acc/proj/module/abc"

      expect(ExAws.Config, :new, fn :s3 -> %{dummy: true} end)

      expect(ExAws.S3, :presigned_url, fn _config, :get, "test-bucket", ^key, opts ->
        assert Keyword.get(opts, :expires_in) == 600
        {:ok, "https://example.com/#{key}?token=xyz"}
      end)

      assert {:ok, url} = S3.presign_download_url(key)
      assert url == "https://example.com/#{key}?token=xyz"
    end

    test "returns presigned URL for xcode_cache type from dedicated bucket" do
      key = "acc/proj/xcode/abc"

      expect(ExAws.Config, :new, fn :s3 -> %{dummy: true} end)

      expect(ExAws.S3, :presigned_url, fn _config, :get, "test-xcode-cache-bucket", ^key, opts ->
        assert Keyword.get(opts, :expires_in) == 600
        {:ok, "https://example.com/#{key}?token=xyz"}
      end)

      assert {:ok, url} = S3.presign_download_url(key, type: :xcode_cache)
      assert url == "https://example.com/#{key}?token=xyz"
    end

    test "propagates error from presigned_url" do
      key = "acc/proj/module/abc"

      expect(ExAws.Config, :new, fn :s3 -> %{dummy: true} end)

      expect(ExAws.S3, :presigned_url, fn _config, :get, "test-bucket", ^key, _opts ->
        {:error, :boom}
      end)

      assert {:error, :boom} = S3.presign_download_url(key)
    end
  end

  describe "remote_accel_path/1" do
    test "builds internal remote path for https URL with query" do
      url = "https://example.com/prefix/acc/proj/xcode/abc?token=xyz"
      assert S3.remote_accel_path(url) == "/internal/remote/https/example.com/prefix/acc/proj/xcode/abc?token=xyz"
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

  describe "exists?/2" do
    test "returns true when file exists in default cache bucket" do
      key = "acc/proj/xcode/abc"

      expect(ExAws.S3, :head_object, fn "test-bucket", ^key ->
        %ExAws.Operation.S3{
          bucket: "test-bucket",
          path: key
        }
      end)

      expect(ExAws, :request, fn _head_object, _opts -> {:ok, %{status_code: 200}} end)

      assert S3.exists?(key) == true
    end

    test "returns true when file exists in xcode_cache bucket" do
      key = "acc/proj/xcode/cas-exists-test"

      expect(ExAws.S3, :head_object, fn "test-xcode-cache-bucket", ^key ->
        %ExAws.Operation.S3{
          bucket: "test-xcode-cache-bucket",
          path: key
        }
      end)

      expect(ExAws, :request, fn _head_object, _opts -> {:ok, %{status_code: 200}} end)

      assert S3.exists?(key, type: :xcode_cache) == true
    end

    test "returns false for xcode_cache when object does not exist in dedicated bucket" do
      key = "acc/proj/xcode/nonexistent-cas"

      expect(ExAws.S3, :head_object, fn "test-xcode-cache-bucket", ^key ->
        %ExAws.Operation.S3{bucket: "test-xcode-cache-bucket", path: key}
      end)

      expect(ExAws, :request, fn _head_object, _opts -> {:error, {:http_error, 404, "Not Found"}} end)

      assert S3.exists?(key, type: :xcode_cache) == false
    end

    test "returns false when file does not exist in S3 (404)" do
      key = "acc/proj/xcode/nonexistent"

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
      key = "acc/proj/xcode/error"

      expect(ExAws.S3, :head_object, fn "test-bucket", ^key ->
        %ExAws.Operation.S3{
          bucket: "test-bucket",
          path: key
        }
      end)

      expect(ExAws, :request, fn _head_object, _opts -> {:error, :timeout} end)

      capture_log(fn ->
        assert S3.exists?(key) == false
      end)
    end

    test "caches results independently per type for the same key" do
      key = "acc/proj/xcode/shared-key"

      expect(ExAws.S3, :head_object, fn "test-bucket", ^key ->
        %ExAws.Operation.S3{bucket: "test-bucket", path: key}
      end)

      expect(ExAws, :request, fn _head_object, _opts -> {:ok, %{status_code: 200}} end)

      assert S3.exists?(key, type: :cache) == true

      expect(ExAws.S3, :head_object, fn "test-xcode-cache-bucket", ^key ->
        %ExAws.Operation.S3{bucket: "test-xcode-cache-bucket", path: key}
      end)

      expect(ExAws, :request, fn _head_object, _opts -> {:error, {:http_error, 404, "Not Found"}} end)

      assert S3.exists?(key, type: :xcode_cache) == false
    end
  end

  describe "upload/1" do
    test "uploads file to S3 when local file exists" do
      key = "test_account/test_project/xcode/TE/ST/test_hash"
      {:ok, tmp_dir} = Briefly.create(directory: true)
      local_path = Path.join(tmp_dir, "test_hash")

      File.write!(local_path, "test content")

      expect(Cache.Disk, :artifact_path, fn ^key -> local_path end)

      expect(Upload, :stream_file, fn ^local_path -> {:stream, local_path} end)

      expect(ExAws.S3, :upload, fn {:stream, ^local_path},
                                   "test-bucket",
                                   ^key,
                                   [timeout: 120_000, max_concurrency: 8] ->
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
      key = "test_account/test_project/xcode/TE/ST/test_hash"

      expect(Cache.Disk, :artifact_path, fn ^key -> "/nonexistent/path/file" end)

      capture_log(fn ->
        assert :ok = S3.upload(key)
      end)
    end

    test "returns error on S3 failure" do
      key = "test_account/test_project/xcode/TE/ST/test_hash"
      {:ok, tmp_dir} = Briefly.create(directory: true)
      local_path = Path.join(tmp_dir, "test_hash")

      File.write!(local_path, "test content")

      expect(Cache.Disk, :artifact_path, fn ^key -> local_path end)

      expect(Upload, :stream_file, fn ^local_path -> {:stream, local_path} end)

      expect(ExAws.S3, :upload, fn {:stream, ^local_path},
                                   "test-bucket",
                                   ^key,
                                   [timeout: 120_000, max_concurrency: 8] ->
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
      key = "test_account/test_project/xcode/TE/ST/test_hash"
      {:ok, tmp_dir} = Briefly.create(directory: true)
      local_path = Path.join(tmp_dir, "test_hash")

      File.write!(local_path, "test content")

      expect(Cache.Disk, :artifact_path, fn ^key -> local_path end)

      expect(Upload, :stream_file, fn ^local_path -> {:stream, local_path} end)

      expect(ExAws.S3, :upload, fn {:stream, ^local_path},
                                   "test-bucket",
                                   ^key,
                                   [timeout: 120_000, max_concurrency: 8] ->
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
      key = "test_account/test_project/xcode/TE/ST/test_hash"
      {:ok, tmp_dir} = Briefly.create(directory: true)
      local_path = Path.join(tmp_dir, "test_hash")

      expect(ExAws.S3, :head_object, fn "test-bucket", ^key ->
        %ExAws.Operation.S3{bucket: "test-bucket", path: key}
      end)

      expect(ExAws, :request, fn %ExAws.Operation.S3{}, _opts -> {:ok, %{status_code: 200}} end)

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
      key = "test_account/test_project/xcode/TE/ST/test_hash"

      expect(ExAws.S3, :head_object, fn "test-bucket", ^key ->
        %ExAws.Operation.S3{bucket: "test-bucket", path: key}
      end)

      expect(ExAws, :request, fn %ExAws.Operation.S3{}, _opts -> {:error, {:http_error, 404, "Not Found"}} end)

      capture_log(fn ->
        assert {:ok, :miss} = S3.download(key)
      end)
    end

    test "returns error on S3 download failure" do
      key = "test_account/test_project/xcode/TE/ST/test_hash"
      {:ok, tmp_dir} = Briefly.create(directory: true)
      local_path = Path.join(tmp_dir, "test_hash")

      expect(ExAws.S3, :head_object, fn "test-bucket", ^key ->
        %ExAws.Operation.S3{bucket: "test-bucket", path: key}
      end)

      expect(ExAws, :request, fn %ExAws.Operation.S3{}, _opts -> {:ok, %{status_code: 200}} end)

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
      key = "test_account/test_project/xcode/TE/ST/test_hash"

      expect(ExAws.S3, :head_object, fn "test-bucket", ^key ->
        %ExAws.Operation.S3{bucket: "test-bucket", path: key}
      end)

      expect(ExAws, :request, fn %ExAws.Operation.S3{}, _opts ->
        {:error, {:http_error, 429, %{body: "Too many requests"}}}
      end)

      capture_log(fn ->
        assert {:error, :rate_limited} = S3.download(key)
      end)
    end

    test "returns :rate_limited error on 429 during download" do
      key = "test_account/test_project/xcode/TE/ST/test_hash"
      {:ok, tmp_dir} = Briefly.create(directory: true)
      local_path = Path.join(tmp_dir, "test_hash")

      expect(ExAws.S3, :head_object, fn "test-bucket", ^key ->
        %ExAws.Operation.S3{bucket: "test-bucket", path: key}
      end)

      expect(ExAws, :request, fn %ExAws.Operation.S3{}, _opts -> {:ok, %{status_code: 200}} end)

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

    test "xcode_cache download from primary bucket returns {:ok, :hit}" do
      key = "test_account/test_project/xcode/TE/ST/test_hash"
      {:ok, tmp_dir} = Briefly.create(directory: true)
      local_path = Path.join(tmp_dir, "test_hash")

      expect(ExAws.S3, :head_object, fn "test-xcode-cache-bucket", ^key ->
        %ExAws.Operation.S3{bucket: "test-xcode-cache-bucket", path: key}
      end)

      expect(ExAws, :request, fn %ExAws.Operation.S3{}, _opts -> {:ok, %{status_code: 200}} end)

      expect(Cache.Disk, :artifact_path, fn ^key -> local_path end)

      expect(ExAws.S3, :download_file, fn "test-xcode-cache-bucket", ^key, ^local_path ->
        {:download_operation, "test-xcode-cache-bucket", key, local_path}
      end)

      expect(ExAws, :request, fn {:download_operation, "test-xcode-cache-bucket", ^key, ^local_path} ->
        File.write!(local_path, "downloaded content")
        {:ok, :done}
      end)

      capture_log(fn ->
        assert {:ok, :hit} = S3.download(key, type: :xcode_cache)
      end)
    end

    test "xcode_cache download returns {:ok, :miss} when not in dedicated bucket" do
      key = "test_account/test_project/xcode/TE/ST/test_hash"

      expect(ExAws.S3, :head_object, fn "test-xcode-cache-bucket", ^key ->
        %ExAws.Operation.S3{bucket: "test-xcode-cache-bucket", path: key}
      end)

      expect(ExAws, :request, fn %ExAws.Operation.S3{}, _opts ->
        {:error, {:http_error, 404, "Not Found"}}
      end)

      capture_log(fn ->
        assert {:ok, :miss} = S3.download(key, type: :xcode_cache)
      end)
    end

    test "xcode_cache download propagates primary bucket HEAD errors instead of falling back" do
      key = "test_account/test_project/xcode/TE/ST/primary-timeout"

      expect(ExAws.S3, :head_object, fn "test-xcode-cache-bucket", ^key ->
        %ExAws.Operation.S3{bucket: "test-xcode-cache-bucket", path: key}
      end)

      expect(ExAws, :request, fn %ExAws.Operation.S3{}, _opts -> {:error, :timeout} end)

      capture_log(fn ->
        assert {:error, :timeout} = S3.download(key, type: :xcode_cache)
      end)
    end

    test "xcode_cache download propagates primary bucket rate limiting instead of falling back" do
      key = "test_account/test_project/xcode/TE/ST/primary-rate-limited"

      expect(ExAws.S3, :head_object, fn "test-xcode-cache-bucket", ^key ->
        %ExAws.Operation.S3{bucket: "test-xcode-cache-bucket", path: key}
      end)

      expect(ExAws, :request, fn %ExAws.Operation.S3{}, _opts ->
        {:error, {:http_error, 429, %{body: "Too many requests"}}}
      end)

      capture_log(fn ->
        assert {:error, :rate_limited} = S3.download(key, type: :xcode_cache)
      end)
    end

    test "xcode_cache download propagates primary bucket 5xx errors instead of falling back" do
      key = "test_account/test_project/xcode/TE/ST/primary-5xx"

      expect(ExAws.S3, :head_object, fn "test-xcode-cache-bucket", ^key ->
        %ExAws.Operation.S3{bucket: "test-xcode-cache-bucket", path: key}
      end)

      expect(ExAws, :request, fn %ExAws.Operation.S3{}, _opts ->
        {:error, {:http_error, 503, "Service Unavailable"}}
      end)

      capture_log(fn ->
        assert {:error, {:http_error, 503, "Service Unavailable"}} = S3.download(key, type: :xcode_cache)
      end)
    end
  end

  describe "delete_all_with_prefix/2" do
    test "deletes all objects with given prefix from default cache bucket" do
      prefix = "test_account/test_project/"

      expect(ExAws, :stream!, fn _operation ->
        [
          %{key: "#{prefix}cas/AB/CD/hash1"},
          %{key: "#{prefix}module/builds/EF/GH/hash2/file.zip"}
        ]
      end)

      expect(ExAws.S3, :delete_multiple_objects, fn "test-bucket", keys ->
        assert keys == ["#{prefix}cas/AB/CD/hash1", "#{prefix}module/builds/EF/GH/hash2/file.zip"]
        {:delete_multiple_operation, "test-bucket", keys}
      end)

      expect(ExAws, :request, fn {:delete_multiple_operation, "test-bucket", _keys} ->
        {:ok, %{}}
      end)

      capture_log(fn ->
        assert {:ok, 2} = S3.delete_all_with_prefix(prefix)
      end)
    end

    test "deletes all objects from xcode_cache bucket when type is :xcode_cache" do
      prefix = "test_account/test_project/"

      expect(ExAws, :stream!, fn _operation ->
        [%{key: "#{prefix}cas/AB/CD/hash1"}]
      end)

      expect(ExAws.S3, :delete_multiple_objects, fn "test-xcode-cache-bucket", keys ->
        assert keys == ["#{prefix}cas/AB/CD/hash1"]
        {:delete_multiple_operation, "test-xcode-cache-bucket", keys}
      end)

      expect(ExAws, :request, fn {:delete_multiple_operation, "test-xcode-cache-bucket", _keys} ->
        {:ok, %{}}
      end)

      capture_log(fn ->
        assert {:ok, 1} = S3.delete_all_with_prefix(prefix, type: :xcode_cache)
      end)
    end

    test "returns {:ok, 0} when no objects exist" do
      prefix = "test_account/test_project/"

      expect(ExAws, :stream!, fn _operation -> [] end)

      capture_log(fn ->
        assert {:ok, 0} = S3.delete_all_with_prefix(prefix)
      end)
    end

    test "returns error when delete_multiple_objects fails" do
      prefix = "test_account/test_project/"

      expect(ExAws, :stream!, fn _operation ->
        [%{key: "#{prefix}cas/AB/CD/hash1"}]
      end)

      expect(ExAws.S3, :delete_multiple_objects, fn "test-bucket", _keys ->
        {:delete_multiple_operation, "test-bucket", []}
      end)

      expect(ExAws, :request, fn {:delete_multiple_operation, "test-bucket", _keys} ->
        {:error, :access_denied}
      end)

      capture_log(fn ->
        assert {:error, :access_denied} = S3.delete_all_with_prefix(prefix)
      end)
    end
  end
end
