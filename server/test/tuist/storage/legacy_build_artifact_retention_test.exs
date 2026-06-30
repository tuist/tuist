defmodule Tuist.Storage.LegacyBuildArtifactRetentionTest do
  use ExUnit.Case, async: false
  use Mimic

  alias Tuist.Accounts.Account
  alias Tuist.Billing.Subscription
  alias Tuist.Environment
  alias Tuist.Repo
  alias Tuist.Storage
  alias Tuist.Storage.LegacyBuildArtifactRetention

  describe "delete_expired/1" do
    test "deletes expired legacy build artifacts from the managed storage bucket" do
      expired_legacy_key = "tuist/app/builds/0123456789abcdef0123456789abcdef/App"
      recent_legacy_key = "tuist/app/builds/fedcba9876543210fedcba9876543210/App"
      current_build_key = "tuist/app/builds/018fb6aa-c19d-7829-8ed3-934375dfba53/build.zip"
      run_artifact_key = "tuist/app/runs/0123456789abcdef0123456789abcdef/log.txt"

      expect(Environment, :s3_bucket_name, fn -> "storage-bucket" end)

      expect(Storage, :list_objects_from_bucket, fn "storage-bucket",
                                                    [prefix: "", max_keys: 1000, continuation_token: nil] ->
        {:ok,
         %{
           body: %{
             contents: [
               %{key: expired_legacy_key, last_modified: DateTime.add(DateTime.utc_now(), -31, :day)},
               %{key: recent_legacy_key, last_modified: DateTime.add(DateTime.utc_now(), -29, :day)},
               %{key: current_build_key, last_modified: DateTime.add(DateTime.utc_now(), -31, :day)},
               %{key: run_artifact_key, last_modified: DateTime.add(DateTime.utc_now(), -31, :day)}
             ],
             is_truncated: true,
             next_continuation_token: "next-page"
           }
         }}
      end)

      expect_accounts_and_plans([%Account{id: 1, name: "tuist"}])

      expect_delete_objects([expired_legacy_key], "storage-bucket")

      assert LegacyBuildArtifactRetention.delete_expired() == {:ok, "next-page"}
    end

    test "deletes legacy build artifacts older than 30 days for paid and free accounts" do
      pro_key = "pro-account/app/builds/0123456789abcdef0123456789abcdef/App"
      air_key = "air-account/app/builds/fedcba9876543210fedcba9876543210/App"

      expect(Environment, :s3_bucket_name, fn -> "storage-bucket" end)

      expect(Storage, :list_objects_from_bucket, fn "storage-bucket",
                                                    [prefix: "", max_keys: 1000, continuation_token: nil] ->
        {:ok,
         %{
           body: %{
             contents: [
               %{key: pro_key, last_modified: DateTime.add(DateTime.utc_now(), -31, :day)},
               %{key: air_key, last_modified: DateTime.add(DateTime.utc_now(), -31, :day)}
             ],
             is_truncated: false
           }
         }}
      end)

      expect_accounts_and_plans(
        [%Account{id: 1, name: "pro-account"}, %Account{id: 2, name: "air-account"}],
        %{1 => :pro}
      )

      expect_delete_objects([pro_key, air_key], "storage-bucket")

      assert LegacyBuildArtifactRetention.delete_expired() == {:ok, nil}
    end

    test "resolves mixed-case object account handles to managed accounts" do
      mixed_case_key = "TUIST/app/builds/0123456789abcdef0123456789abcdef/App"

      expect(Environment, :s3_bucket_name, fn -> "storage-bucket" end)

      expect(Storage, :list_objects_from_bucket, fn "storage-bucket",
                                                    [prefix: "", max_keys: 1000, continuation_token: nil] ->
        {:ok,
         %{
           body: %{
             contents: [
               %{key: mixed_case_key, last_modified: DateTime.add(DateTime.utc_now(), -31, :day)}
             ],
             is_truncated: false
           }
         }}
      end)

      expect_accounts_and_plans([%Account{id: 1, name: "tuist"}])

      expect_delete_objects([mixed_case_key], "storage-bucket")

      assert LegacyBuildArtifactRetention.delete_expired() == {:ok, nil}
    end

    test "deletes orphaned legacy build artifacts older than 30 days" do
      expired_orphan_key = "deleted-account/app/builds/0123456789abcdef0123456789abcdef/App"
      recent_orphan_key = "deleted-account/app/builds/fedcba9876543210fedcba9876543210/App"
      current_build_key = "deleted-account/app/builds/018fb6aa-c19d-7829-8ed3-934375dfba53/build.zip"

      expect(Environment, :s3_bucket_name, fn -> "storage-bucket" end)

      expect(Storage, :list_objects_from_bucket, fn "storage-bucket",
                                                    [prefix: "", max_keys: 1000, continuation_token: nil] ->
        {:ok,
         %{
           body: %{
             contents: [
               %{key: expired_orphan_key, last_modified: DateTime.add(DateTime.utc_now(), -31, :day)},
               %{key: recent_orphan_key, last_modified: DateTime.add(DateTime.utc_now(), -29, :day)},
               %{key: current_build_key, last_modified: DateTime.add(DateTime.utc_now(), -31, :day)}
             ],
             is_truncated: false
           }
         }}
      end)

      expect(Repo, :all, fn _query -> [] end)

      expect_delete_objects([expired_orphan_key], "storage-bucket")

      assert LegacyBuildArtifactRetention.delete_expired() == {:ok, nil}
    end

    test "skips cleanup when the managed storage bucket is not configured" do
      expect(Environment, :s3_bucket_name, fn -> nil end)

      assert LegacyBuildArtifactRetention.delete_expired() == :ok
    end
  end

  defp expect_accounts_and_plans(accounts, plans_by_account_id \\ %{}) do
    expect(Repo, :all, 2, fn
      %Ecto.Query{from: %{source: {"accounts", Account}}} ->
        accounts

      %Ecto.Query{from: %{source: {"subscriptions", Subscription}}} ->
        Map.to_list(plans_by_account_id)
    end)
  end

  defp expect_delete_objects(keys, bucket_name) do
    expect(Storage, :delete_objects_from_bucket, fn ^keys, ^bucket_name, opts ->
      assert opts[:receive_timeout] == 60_000
      assert opts[:task_timeout] == 65_000
      :ok
    end)
  end
end
