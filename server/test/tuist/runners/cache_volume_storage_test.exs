defmodule Tuist.Runners.CacheVolumeStorageTest do
  use ExUnit.Case, async: true
  use Mimic

  alias Tuist.Accounts
  alias Tuist.Accounts.Account
  alias Tuist.Runners
  alias Tuist.Storage

  test "Linux and macOS use the same immutable object prefix and signed checksums" do
    account = %Account{id: 123}
    digest = String.duplicate("a", 40)
    content = String.duplicate("b", 64)
    checksum = content |> Base.decode16!(case: :lower) |> Base.encode64()
    stub(Accounts, :get_account_by_id, fn 123 -> {:ok, account} end)
    stub(Storage, :supports_signed_upload_headers?, fn ^account -> true end)

    for name <- ["tuist-cache", "repo-0123456789abcdef", "linux-" <> String.duplicate("c", 64)] do
      key = "runner-volume-masters/123/#{name}/#{digest}-#{content}.image"

      expect(Storage, :generate_upload_url, fn ^key, ^account, options ->
        assert options[:signed_headers] == [{"x-amz-checksum-sha256", checksum}]
        "https://1.1.1.1/image"
      end)

      assert {:ok, "https://1.1.1.1/image", ^checksum} = Runners.volume_master_upload_url(123, name, digest, content)
      expect(Storage, :generate_download_url, fn ^key, ^account, _ -> "https://1.1.1.1/image" end)
      assert {:ok, "https://1.1.1.1/image"} = Runners.volume_master_download_url(123, name, digest, content)
    end
  end

  test "invalid storage names and digests cannot become object keys" do
    for name <- ["linux-../other", "linux-", "../tuist-cache"] do
      assert :error = Runners.volume_master_upload_url(123, name, String.duplicate("a", 40), String.duplicate("b", 64))
      assert :error = Runners.volume_master_download_url(123, name, String.duplicate("a", 40), String.duplicate("b", 64))
    end

    assert :error = Runners.volume_master_download_url(123, "tuist-cache", "../bad", String.duplicate("b", 64))
  end
end
