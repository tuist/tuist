defmodule Tuist.Runners.Workers.AbortVolumeMasterUploadWorkerTest do
  use TuistTestSupport.Cases.DataCase, async: true
  use Mimic

  alias Tuist.Runners.Workers.AbortVolumeMasterUploadWorker
  alias Tuist.Storage
  alias TuistTestSupport.Fixtures.AccountsFixtures

  setup do
    %{account: account} = AccountsFixtures.organization_fixture(preload: [:account])

    %{
      account: account,
      args: %{account_id: account.id, object_key: "runner-volume-masters/1/macos-a/b.image", upload_id: "u"}
    }
  end

  test "aborts the upload in the account's storage", %{account: account, args: args} do
    expect(Storage, :multipart_abort, fn "runner-volume-masters/1/macos-a/b.image", "u", actor ->
      assert actor.id == account.id
      :ok
    end)

    assert perform_job(AbortVolumeMasterUploadWorker, args) == :ok
  end

  test "retries a storage failure", %{args: args} do
    stub(Storage, :multipart_abort, fn _, _, _ -> {:error, :timeout} end)
    assert perform_job(AbortVolumeMasterUploadWorker, args) == {:error, :timeout}
  end

  test "skips an account that no longer exists", %{args: args} do
    reject(&Storage.multipart_abort/3)
    assert perform_job(AbortVolumeMasterUploadWorker, %{args | account_id: -1}) == :ok
  end
end
