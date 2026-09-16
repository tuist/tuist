defmodule Tuist.Runners.GitLab.CacheTest do
  use TuistTestSupport.Cases.DataCase, async: true
  use Mimic

  alias Tuist.Runners.GitLab.Cache
  alias Tuist.Storage
  alias TuistTestSupport.Fixtures.AccountsFixtures

  setup do
    %{account: account} = AccountsFixtures.organization_fixture(preload: [:account])
    %{account: account, identity: %{account_id: account.id, gitlab_project_id: 123, ref_protected: true}}
  end

  test "presigns the account's archive in the job's ref namespace", %{account: account, identity: identity} do
    protected_key = "runner-gitlab-cache/#{account.name}/123/protected/gems-protected"
    unprotected_key = "runner-gitlab-cache/#{account.name}/123/unprotected/gems-protected"

    expect(Storage, :generate_download_url, 2, fn key, actor, opts ->
      assert actor.id == account.id
      assert opts[:expires_in] == 3600
      "https://storage.example.com/#{key}?signature=get"
    end)

    expect(Storage, :generate_upload_url, 2, fn key, actor, opts ->
      assert actor.id == account.id
      assert opts[:expires_in] == 3600
      "https://storage.example.com/#{key}?signature=put"
    end)

    assert {:ok, protected} = Cache.urls(identity, "project/123/gems-protected", expires_in: 3600)
    assert protected.download_url == "https://storage.example.com/#{protected_key}?signature=get"
    assert protected.upload_url == "https://storage.example.com/#{protected_key}?signature=put"

    # A pipeline chooses its cache key, so an unprotected ref naming a key
    # that ends in `-protected` still lands in its own namespace.
    assert {:ok, unprotected} =
             Cache.urls(%{identity | ref_protected: false}, "project/123/gems-protected", expires_in: 3600)

    assert unprotected.upload_url == "https://storage.example.com/#{unprotected_key}?signature=put"
  end

  test "rejects object names outside the job's project", %{identity: identity} do
    reject(&Storage.generate_download_url/3)
    reject(&Storage.generate_upload_url/3)

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
      assert Cache.urls(identity, object_name) == {:error, :invalid_object_name}, inspect(object_name)
    end
  end

  test "is unavailable to a token minted without a cache scope", %{account: account} do
    reject(&Storage.generate_download_url/3)
    assert Cache.urls(%{account_id: account.id}, "project/123/gems") == {:error, :cache_unavailable}
  end

  test "refuses to hand out URLs for a private storage host", %{identity: identity} do
    stub(Storage, :generate_download_url, fn _, _, _ -> "https://storage.example.com/object" end)
    stub(Storage, :generate_upload_url, fn _, _, _ -> "http://10.0.0.5/object" end)

    assert Cache.urls(identity, "project/123/gems") == {:error, :cache_unavailable}
  end

  test "bounds how long a URL stays valid", %{identity: identity} do
    test_pid = self()

    stub(Storage, :generate_download_url, fn _, _, opts ->
      send(test_pid, {:expires_in, opts[:expires_in]})
      "https://storage.example.com/object"
    end)

    stub(Storage, :generate_upload_url, fn _, _, _ -> "https://storage.example.com/object" end)

    cases = [{60, 60}, {999_999, 43_200}, {0, 10_800}, {-5, 10_800}, {"3600", 10_800}, {nil, 10_800}]

    for {requested, expected} <- cases do
      assert {:ok, _} = Cache.urls(identity, "project/123/gems", expires_in: requested)
      assert_receive {:expires_in, ^expected}
    end
  end
end
