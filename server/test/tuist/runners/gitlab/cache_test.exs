defmodule Tuist.Runners.GitLab.CacheTest do
  use TuistTestSupport.Cases.DataCase, async: true
  use Mimic

  alias Tuist.Runners.GitLab.Cache
  alias Tuist.Runners.Workers.AbortGitLabCacheUploadWorker
  alias Tuist.Storage
  alias TuistTestSupport.Fixtures.AccountsFixtures

  setup do
    %{account: account} = AccountsFixtures.organization_fixture(preload: [:account])

    %{
      account: account,
      identity: %{account_id: account.id, gitlab_project_id: 123, ref_protected: true},
      key: "runner-gitlab-cache/#{account.name}/123/protected/gems-protected"
    }
  end

  describe "download_url/3" do
    test "presigns the account's archive in the job's ref namespace", %{account: account, identity: identity, key: key} do
      unprotected_key = "runner-gitlab-cache/#{account.name}/123/unprotected/gems-protected"

      expect(Storage, :generate_download_url, 2, fn object_key, actor, opts ->
        assert actor.id == account.id
        assert opts[:expires_in] == 3600
        "https://storage.example.com/#{object_key}?signature=get"
      end)

      assert Cache.download_url(identity, "project/123/gems-protected", expires_in: 3600) ==
               {:ok, "https://storage.example.com/#{key}?signature=get"}

      # A pipeline chooses its cache key, so an unprotected ref naming a key
      # that ends in `-protected` still lands in its own namespace.
      assert Cache.download_url(%{identity | ref_protected: false}, "project/123/gems-protected", expires_in: 3600) ==
               {:ok, "https://storage.example.com/#{unprotected_key}?signature=get"}
    end

    test "rejects object names outside the job's project", %{identity: identity} do
      reject(&Storage.generate_download_url/3)

      for object_name <- [
            "project/124/gems",
            "project/123",
            "project/123/",
            "project/123/..",
            "project/123/.",
            "project/123/nested/key",
            "project/123/back\\slash",
            "project/123/line\nbreak",
            "project/123/" <> String.duplicate("a", 513),
            "project/123/" <> <<0xFF>>,
            "runner/token/project/123/gems",
            nil
          ] do
        assert Cache.download_url(identity, object_name) == {:error, :invalid_object_name}, inspect(object_name)
      end
    end

    test "is unavailable to a token minted without a cache scope", %{account: account} do
      reject(&Storage.generate_download_url/3)
      assert Cache.download_url(%{account_id: account.id}, "project/123/gems") == {:error, :cache_unavailable}
    end

    test "refuses to hand out a URL for a private storage host", %{identity: identity} do
      stub(Storage, :generate_download_url, fn _, _, _ -> "http://10.0.0.5/object" end)
      assert Cache.download_url(identity, "project/123/gems") == {:error, :cache_unavailable}
    end

    test "bounds how long the URL stays valid", %{identity: identity} do
      test_pid = self()

      stub(Storage, :generate_download_url, fn _, _, opts ->
        send(test_pid, {:expires_in, opts[:expires_in]})
        "https://storage.example.com/object"
      end)

      cases = [{60, 60}, {999_999, 43_200}, {0, 10_800}, {-5, 10_800}, {"3600", 10_800}, {nil, 10_800}]

      for {requested, expected} <- cases do
        assert {:ok, _} = Cache.download_url(identity, "project/123/gems", expires_in: requested)
        assert_receive {:expires_in, ^expected}
      end
    end
  end

  describe "multipart uploads" do
    test "start, presign parts and complete against the scoped key", %{account: account, identity: identity, key: key} do
      expect(Storage, :multipart_start, fn ^key, actor ->
        assert actor.id == account.id
        {:ok, "upload-1"}
      end)

      expect(Storage, :multipart_generate_url, fn ^key, "upload-1", 2, _actor, opts ->
        assert opts[:expires_in] == 3600
        "https://storage.example.com/#{key}?partNumber=2"
      end)

      expect(Storage, :multipart_complete_upload, fn ^key, "upload-1", parts, _actor ->
        assert parts == [{1, "etag-1"}, {2, "etag-2"}]
        :ok
      end)

      assert Cache.start_upload(identity, "project/123/gems-protected") == {:ok, "upload-1"}

      assert_enqueued(
        worker: AbortGitLabCacheUploadWorker,
        args: %{account_id: account.id, object_key: key, upload_id: "upload-1"}
      )

      assert Cache.upload_part_url(identity, "project/123/gems-protected", "upload-1", 2) ==
               {:ok, "https://storage.example.com/#{key}?partNumber=2"}

      parts = [%{"part_number" => 2, "etag" => "etag-2"}, %{"part_number" => 1, "etag" => "etag-1"}]
      assert Cache.complete_upload(identity, "project/123/gems-protected", "upload-1", parts) == :ok
    end

    test "schedules the abort a day out, past any job's lifetime", %{identity: identity} do
      stub(Storage, :multipart_start, fn _, _ -> {:ok, "upload-1"} end)

      assert {:ok, _} = Cache.start_upload(identity, "project/123/gems")

      assert_enqueued(
        worker: AbortGitLabCacheUploadWorker,
        scheduled_at: {DateTime.add(DateTime.utc_now(), 24 * 60 * 60, :second), delta: 60}
      )
    end

    test "rejects malformed uploads", %{identity: identity} do
      reject(&Storage.multipart_generate_url/5)
      reject(&Storage.multipart_complete_upload/4)

      for part_number <- [0, 10_001, "1", nil] do
        assert Cache.upload_part_url(identity, "project/123/gems", "upload-1", part_number) == {:error, :invalid_upload}
      end

      for upload_id <- ["", nil, String.duplicate("a", 1025)] do
        assert Cache.upload_part_url(identity, "project/123/gems", upload_id, 1) == {:error, :invalid_upload}
      end

      for parts <- [
            [],
            nil,
            [%{"part_number" => 1}],
            [%{"part_number" => 1, "etag" => ""}],
            [%{"part_number" => 1, "etag" => "a"}, %{"part_number" => 1, "etag" => "b"}],
            [%{"part_number" => "1", "etag" => "a"}]
          ] do
        assert Cache.complete_upload(identity, "project/123/gems", "upload-1", parts) == {:error, :invalid_upload},
               inspect(parts)
      end
    end

    test "cannot upload another project's object", %{identity: identity} do
      reject(&Storage.multipart_start/2)
      assert Cache.start_upload(identity, "project/999/gems") == {:error, :invalid_object_name}
      refute_enqueued(worker: AbortGitLabCacheUploadWorker)
    end

    test "distinguishes storage failures from a finished upload", %{identity: identity} do
      stub(Storage, :multipart_start, fn _, _ -> {:error, :timeout} end)
      stub(Storage, :multipart_abort, fn _, _, _ -> {:error, :timeout} end)
      parts = [%{"part_number" => 1, "etag" => "etag-1"}]

      assert Cache.start_upload(identity, "project/123/gems") == {:error, :storage_unavailable}
      refute_enqueued(worker: AbortGitLabCacheUploadWorker)
      assert Cache.abort_upload(identity, "project/123/gems", "upload-1") == {:error, :storage_unavailable}

      stub(Storage, :multipart_complete_upload, fn _, _, _, _ -> {:error, :multipart_upload_not_found} end)
      assert Cache.complete_upload(identity, "project/123/gems", "upload-1", parts) == {:error, :upload_not_found}

      stub(Storage, :multipart_complete_upload, fn _, _, _, _ -> {:error, :timeout} end)
      assert Cache.complete_upload(identity, "project/123/gems", "upload-1", parts) == {:error, :storage_unavailable}
    end

    test "aborts the scoped upload", %{identity: identity, key: key} do
      expect(Storage, :multipart_abort, fn ^key, "upload-1", _actor -> :ok end)
      assert Cache.abort_upload(identity, "project/123/gems-protected", "upload-1") == :ok
    end
  end
end
