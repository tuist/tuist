defmodule Tuist.Storage.AccountRetentionTest do
  use TuistTestSupport.Cases.DataCase, async: true
  use Mimic

  alias Tuist.Accounts
  alias Tuist.Environment
  alias Tuist.Storage
  alias Tuist.Storage.CacheArtifactRetention
  alias TuistTestSupport.Fixtures.AccountsFixtures

  test "bucket cleanup applies the same account ceiling to current and retained handles" do
    account = AccountsFixtures.account_fixture()
    other = AccountsFixtures.account_fixture()
    old_handle = account.name
    {:ok, account} = Accounts.update_account_retention(account, %{artifact_retention_days: 7})
    {:ok, account} = Accounts.update_account(account, %{name: "renamed-#{account.id}"})

    old_key = "#{old_handle}/app/xcode/AB/CD/ABCD"
    current_key = "#{account.name}/app/xcode/EF/GH/EFGH"
    recent_key = "#{old_handle}/app/xcode/IJ/KL/IJKL"
    other_key = "#{other.name}/app/xcode/MN/OP/MNOP"
    now = DateTime.utc_now()

    expect(Environment, :cache_xcode_s3_bucket_name, fn -> "cache-bucket" end)

    expect(Storage, :list_objects_from_bucket, fn "cache-bucket", _opts ->
      {:ok,
       %{
         body: %{
           contents: [
             %{key: old_key, last_modified: DateTime.add(now, -8, :day)},
             %{key: current_key, last_modified: DateTime.add(now, -8, :day)},
             %{key: recent_key, last_modified: DateTime.add(now, -6, :day)},
             %{key: other_key, last_modified: DateTime.add(now, -8, :day)}
           ]
         }
       }}
    end)

    expect(Storage, :delete_objects_from_bucket, fn keys, "cache-bucket", _opts ->
      assert Enum.sort(keys) == Enum.sort([old_key, current_key])
      :ok
    end)

    assert CacheArtifactRetention.delete_expired(:xcode_cache) == {:ok, nil}
  end
end
