defmodule Tuist.Runners.Workers.PurgeBuiltinVolumeMastersWorkerTest do
  use TuistTestSupport.Cases.DataCase, async: true

  import Mimic
  import TuistTestSupport.Fixtures.AccountsFixtures

  alias Tuist.Runners.Workers.PurgeBuiltinVolumeMastersWorker
  alias Tuist.Storage

  setup :verify_on_exit!

  test "deletes only the account's built-in master keys, across pages" do
    account = account_fixture()
    prefix = "runner-volume-masters/#{account.id}/"
    custom = "macos-" <> String.duplicate("a", 64)
    test_pid = self()

    expect(Storage, :list_objects, fn ^prefix, actor, opts ->
      assert actor.id == account.id
      assert opts[:continuation_token] == nil

      {:ok,
       %{
         body: %{
           contents: [
             %{key: prefix <> "tuist-cache/" <> String.duplicate("1", 40) <> ".image"},
             %{key: prefix <> "tuist-cache.zip"},
             %{key: prefix <> "#{custom}/" <> String.duplicate("2", 40) <> ".image"}
           ],
           is_truncated: "true",
           next_continuation_token: "page-2"
         }
       }}
    end)

    expect(Storage, :list_objects, fn ^prefix, _actor, opts ->
      assert opts[:continuation_token] == "page-2"

      {:ok,
       %{
         body: %{
           contents: [
             %{key: prefix <> "repo-0123456789abcdef/" <> String.duplicate("3", 40) <> ".image"},
             %{key: prefix <> "repo-not-a-hash/" <> String.duplicate("4", 40) <> ".image"},
             %{key: prefix <> "linux-" <> String.duplicate("b", 64) <> "/" <> String.duplicate("5", 40) <> ".image"}
           ],
           is_truncated: "false"
         }
       }}
    end)

    stub(Storage, :delete_objects, fn keys, _actor ->
      send(test_pid, {:deleted, keys})
      :ok
    end)

    assert :ok = perform_job(PurgeBuiltinVolumeMastersWorker, %{account_id: account.id})

    assert_received {:deleted, first_page}
    assert first_page == [prefix <> "tuist-cache/" <> String.duplicate("1", 40) <> ".image", prefix <> "tuist-cache.zip"]

    assert_received {:deleted, second_page}
    assert second_page == [prefix <> "repo-0123456789abcdef/" <> String.duplicate("3", 40) <> ".image"]
  end

  test "returns the storage error so the job is retried" do
    account = account_fixture()

    stub(Storage, :list_objects, fn _prefix, _actor, _opts ->
      {:ok, %{body: %{contents: [%{key: "runner-volume-masters/#{account.id}/tuist-cache.zip"}]}}}
    end)

    stub(Storage, :delete_objects, fn _keys, _actor -> {:error, :timeout} end)

    assert {:error, :timeout} = perform_job(PurgeBuiltinVolumeMastersWorker, %{account_id: account.id})
  end

  test "does nothing for an account that no longer exists" do
    reject(&Storage.list_objects/3)

    assert :ok = perform_job(PurgeBuiltinVolumeMastersWorker, %{account_id: -1})
  end
end
