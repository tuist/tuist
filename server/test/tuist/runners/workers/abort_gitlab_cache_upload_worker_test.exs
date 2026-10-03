defmodule Tuist.Runners.Workers.AbortGitLabCacheUploadWorkerTest do
  use TuistTestSupport.Cases.DataCase, async: true
  use Mimic

  alias Tuist.Runners.Workers.AbortGitLabCacheUploadWorker
  alias Tuist.Storage
  alias TuistTestSupport.Fixtures.AccountsFixtures

  setup do
    %{account: account} = AccountsFixtures.organization_fixture(preload: [:account])

    %{
      account: account,
      args: %{account_id: account.id, object_key: "runner-gitlab-cache/a/1/protected/k", upload_id: "u"}
    }
  end

  test "aborts the upload in the account's storage", %{account: account, args: args} do
    expect(Storage, :multipart_abort, fn "runner-gitlab-cache/a/1/protected/k", "u", actor ->
      assert actor.id == account.id
      :ok
    end)

    assert perform_job(AbortGitLabCacheUploadWorker, args) == :ok
  end

  test "retries a storage failure", %{args: args} do
    stub(Storage, :multipart_abort, fn _, _, _ -> {:error, :timeout} end)
    assert perform_job(AbortGitLabCacheUploadWorker, args) == {:error, :timeout}
  end

  test "skips an account that no longer exists", %{args: args} do
    reject(&Storage.multipart_abort/3)
    assert perform_job(AbortGitLabCacheUploadWorker, %{args | account_id: -1}) == :ok
  end
end
