defmodule Cache.S3Test do
  use ExUnit.Case, async: false
  use Mimic

  alias Cache.S3

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

    # We do not test missing bucket; runtime enforces presence.
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
end
