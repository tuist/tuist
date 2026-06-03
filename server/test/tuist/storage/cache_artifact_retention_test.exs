defmodule Tuist.Storage.CacheArtifactRetentionTest do
  use ExUnit.Case, async: false
  use Mimic

  alias Tuist.Accounts.Account
  alias Tuist.Billing.Subscription
  alias Tuist.Environment
  alias Tuist.Repo
  alias Tuist.Storage
  alias Tuist.Storage.CacheArtifactRetention

  describe "delete_expired/2" do
    test "deletes expired objects for the requested cache artifact type" do
      expired_xcode_key = "tuist/app/xcode/AB/CD/ABCD"
      recent_xcode_key = "tuist/app/xcode/EF/GH/EFGH"
      expired_gradle_key = "tuist/app/gradle/AB/CD/ABCD"

      expect(Environment, :cache_xcode_s3_bucket_name, fn -> "xcode-cache-bucket" end)

      expect(Storage, :list_objects_from_bucket, fn "xcode-cache-bucket",
                                                    [prefix: "", max_keys: 1000, continuation_token: nil] ->
        {:ok,
         %{
           body: %{
             contents: [
               %{key: expired_xcode_key, last_modified: DateTime.add(DateTime.utc_now(), -15, :day)},
               %{key: recent_xcode_key, last_modified: DateTime.add(DateTime.utc_now(), -13, :day)},
               %{key: expired_gradle_key, last_modified: DateTime.add(DateTime.utc_now(), -15, :day)}
             ],
             is_truncated: true,
             next_continuation_token: "next-page"
           }
         }}
      end)

      expect_accounts_and_plans([%Account{id: 1, name: "tuist"}])

      expect(Storage, :delete_objects_from_bucket, fn [^expired_xcode_key], "xcode-cache-bucket" ->
        :ok
      end)

      assert CacheArtifactRetention.delete_expired(:xcode_cache) == {:ok, "next-page"}
    end

    test "uses the cache bucket for Gradle and module artifacts" do
      expired_module_key = "tuist/app/module/builds/AB/CD/ABCD/module.zip"

      expect(Environment, :cache_s3_bucket_name, fn -> "cache-bucket" end)

      expect(Storage, :list_objects_from_bucket, fn "cache-bucket",
                                                    [prefix: "", max_keys: 1000, continuation_token: "cursor"] ->
        {:ok,
         %{
           body: %{
             contents: [
               %{key: expired_module_key, last_modified: DateTime.add(DateTime.utc_now(), -15, :day)}
             ],
             is_truncated: false
           }
         }}
      end)

      expect_accounts_and_plans([%Account{id: 1, name: "tuist"}])

      expect(Storage, :delete_objects_from_bucket, fn [^expired_module_key], "cache-bucket" ->
        :ok
      end)

      assert CacheArtifactRetention.delete_expired(:xcode_module, continuation_token: "cursor") == {:ok, nil}
    end

    test "continues pagination when ExAws reports the truncated flag as a string" do
      expired_xcode_key = "tuist/app/xcode/AB/CD/ABCD"

      expect(Environment, :cache_xcode_s3_bucket_name, fn -> "xcode-cache-bucket" end)

      expect(Storage, :list_objects_from_bucket, fn "xcode-cache-bucket",
                                                    [prefix: "", max_keys: 1000, continuation_token: nil] ->
        {:ok,
         %{
           body: %{
             contents: [
               %{key: expired_xcode_key, last_modified: DateTime.add(DateTime.utc_now(), -15, :day)}
             ],
             is_truncated: "true",
             next_continuation_token: "next-page"
           }
         }}
      end)

      expect_accounts_and_plans([%Account{id: 1, name: "tuist"}])

      expect(Storage, :delete_objects_from_bucket, fn [^expired_xcode_key], "xcode-cache-bucket" ->
        :ok
      end)

      assert CacheArtifactRetention.delete_expired(:xcode_cache) == {:ok, "next-page"}
    end

    test "skips objects whose account handle does not resolve to a known account" do
      orphan_key = "deleted-account/app/xcode/AB/CD/ABCD"

      expect(Environment, :cache_xcode_s3_bucket_name, fn -> "xcode-cache-bucket" end)

      expect(Storage, :list_objects_from_bucket, fn "xcode-cache-bucket",
                                                    [prefix: "", max_keys: 1000, continuation_token: nil] ->
        {:ok,
         %{
           body: %{
             contents: [
               %{key: orphan_key, last_modified: DateTime.add(DateTime.utc_now(), -3650, :day)}
             ],
             is_truncated: false
           }
         }}
      end)

      expect(Repo, :all, fn _query -> [] end)

      expect(Storage, :delete_objects_from_bucket, fn [], "xcode-cache-bucket" -> :ok end)

      assert CacheArtifactRetention.delete_expired(:xcode_cache) == {:ok, nil}
    end

    test "skips cleanup when the cache bucket is not configured" do
      expect(Environment, :cache_s3_bucket_name, fn -> nil end)

      assert CacheArtifactRetention.delete_expired(:gradle) == :ok
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
end
