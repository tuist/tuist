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

      expect_delete_objects([expired_xcode_key], "xcode-cache-bucket")

      assert CacheArtifactRetention.delete_expired(:xcode_cache) == {:ok, "next-page"}
    end

    test "deletes expired legacy CAS objects from the cache bucket" do
      expired_cas_key = "tuist/app/cas/AB/CD/ABCD"
      recent_cas_key = "tuist/app/cas/EF/GH/EFGH"
      expired_module_key = "tuist/app/module/builds/AB/CD/ABCD/module.zip"

      expect(Environment, :cache_s3_bucket_name, fn -> "cache-bucket" end)

      expect(Storage, :list_objects_from_bucket, fn "cache-bucket",
                                                    [prefix: "", max_keys: 1000, continuation_token: nil] ->
        {:ok,
         %{
           body: %{
             contents: [
               %{key: expired_cas_key, last_modified: DateTime.add(DateTime.utc_now(), -15, :day)},
               %{key: recent_cas_key, last_modified: DateTime.add(DateTime.utc_now(), -13, :day)},
               %{key: expired_module_key, last_modified: DateTime.add(DateTime.utc_now(), -15, :day)}
             ],
             is_truncated: false
           }
         }}
      end)

      expect_accounts_and_plans([%Account{id: 1, name: "tuist"}])

      expect_delete_objects([expired_cas_key], "cache-bucket")

      assert CacheArtifactRetention.delete_expired(:cas) == {:ok, nil}
    end

    test "uses the cache bucket for module artifacts" do
      expired_module_key = "tuist/app/module/builds/AB/CD/ABCD/module.zip"
      expired_gradle_key = "tuist/app/gradle/AB/CD/ABCD"

      expect(Environment, :cache_s3_bucket_name, fn -> "cache-bucket" end)

      expect(Storage, :list_objects_from_bucket, fn "cache-bucket",
                                                    [prefix: "", max_keys: 1000, continuation_token: "cursor"] ->
        {:ok,
         %{
           body: %{
             contents: [
               %{key: expired_module_key, last_modified: DateTime.add(DateTime.utc_now(), -15, :day)},
               %{key: expired_gradle_key, last_modified: DateTime.add(DateTime.utc_now(), -15, :day)}
             ],
             is_truncated: false
           }
         }}
      end)

      expect_accounts_and_plans([%Account{id: 1, name: "tuist"}])

      expect_delete_objects([expired_module_key], "cache-bucket")

      assert CacheArtifactRetention.delete_expired(:xcode_module, continuation_token: "cursor") == {:ok, nil}
    end

    test "uses the cache bucket for Gradle artifacts" do
      expired_gradle_key = "tuist/app/gradle/AB/CD/ABCD"
      expired_module_key = "tuist/app/module/builds/AB/CD/ABCD/module.zip"

      expect(Environment, :cache_s3_bucket_name, fn -> "cache-bucket" end)

      expect(Storage, :list_objects_from_bucket, fn "cache-bucket",
                                                    [prefix: "", max_keys: 1000, continuation_token: nil] ->
        {:ok,
         %{
           body: %{
             contents: [
               %{key: expired_gradle_key, last_modified: DateTime.add(DateTime.utc_now(), -15, :day)},
               %{key: expired_module_key, last_modified: DateTime.add(DateTime.utc_now(), -15, :day)}
             ],
             is_truncated: false
           }
         }}
      end)

      expect_accounts_and_plans([%Account{id: 1, name: "tuist"}])

      expect_delete_objects([expired_gradle_key], "cache-bucket")

      assert CacheArtifactRetention.delete_expired(:gradle) == {:ok, nil}
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

      expect_delete_objects([expired_xcode_key], "xcode-cache-bucket")

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

      expect_delete_objects([], "xcode-cache-bucket")

      assert CacheArtifactRetention.delete_expired(:xcode_cache) == {:ok, nil}
    end

    test "skips objects for accounts with custom S3 storage configured" do
      custom_storage_key = "custom-storage-account/app/xcode/AB/CD/ABCD"
      managed_storage_key = "managed-storage-account/app/xcode/EF/GH/EFGH"

      expect(Environment, :cache_xcode_s3_bucket_name, fn -> "xcode-cache-bucket" end)

      expect(Storage, :list_objects_from_bucket, fn "xcode-cache-bucket",
                                                    [prefix: "", max_keys: 1000, continuation_token: nil] ->
        {:ok,
         %{
           body: %{
             contents: [
               %{key: custom_storage_key, last_modified: DateTime.add(DateTime.utc_now(), -3650, :day)},
               %{key: managed_storage_key, last_modified: DateTime.add(DateTime.utc_now(), -3650, :day)}
             ],
             is_truncated: false
           }
         }}
      end)

      expect_accounts_and_plans([
        %Account{
          id: 1,
          name: "custom-storage-account",
          s3_bucket_name: "custom-bucket",
          s3_access_key_id: "CUSTOM_ACCESS_KEY",
          s3_secret_access_key: "CUSTOM_SECRET_KEY"
        },
        %Account{id: 2, name: "managed-storage-account"}
      ])

      expect_delete_objects([managed_storage_key], "xcode-cache-bucket")

      assert CacheArtifactRetention.delete_expired(:xcode_cache) == {:ok, nil}
    end

    test "resolves mixed-case object account handles to managed accounts" do
      mixed_case_key = "TUIST/app/xcode/AB/CD/ABCD"

      expect(Environment, :cache_xcode_s3_bucket_name, fn -> "xcode-cache-bucket" end)

      expect(Storage, :list_objects_from_bucket, fn "xcode-cache-bucket",
                                                    [prefix: "", max_keys: 1000, continuation_token: nil] ->
        {:ok,
         %{
           body: %{
             contents: [
               %{key: mixed_case_key, last_modified: DateTime.add(DateTime.utc_now(), -15, :day)}
             ],
             is_truncated: false
           }
         }}
      end)

      expect_accounts_and_plans([%Account{id: 1, name: "tuist"}])

      expect_delete_objects([mixed_case_key], "xcode-cache-bucket")

      assert CacheArtifactRetention.delete_expired(:xcode_cache) == {:ok, nil}
    end

    test "skips cleanup when the cache bucket is not configured" do
      expect(Environment, :cache_s3_bucket_name, fn -> nil end)

      assert CacheArtifactRetention.delete_expired(:gradle) == :ok
    end

    test "uses the Azure Blob container when Azure Blob is the server artifact provider" do
      expired_gradle_key = "tuist/app/gradle/AB/CD/ABCD"

      expect(Environment, :object_storage_provider, fn -> :azure_blob end)
      expect(Environment, :azure_blob_container_name, fn -> "azure-artifacts" end)

      expect(Storage, :list_objects_from_bucket, fn "azure-artifacts", opts ->
        assert opts[:prefix] == ""
        assert opts[:max_keys] == 1000
        assert opts[:continuation_token] == nil
        assert opts[:storage_provider] == :azure_blob

        {:ok,
         %{
           body: %{
             contents: [
               %{key: expired_gradle_key, last_modified: DateTime.add(DateTime.utc_now(), -15, :day)}
             ],
             is_truncated: false
           }
         }}
      end)

      expect_accounts_and_plans([%Account{id: 1, name: "tuist"}])

      expect_delete_objects([expired_gradle_key], "azure-artifacts", :azure_blob)

      assert CacheArtifactRetention.delete_expired(:gradle) == {:ok, nil}
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

  defp expect_delete_objects(keys, bucket_name, storage_provider \\ :s3) do
    expect(Storage, :delete_objects_from_bucket, fn ^keys, ^bucket_name, opts ->
      assert opts[:receive_timeout] == 60_000
      assert opts[:task_timeout] == 65_000

      if storage_provider == :s3 do
        refute Keyword.has_key?(opts, :storage_provider)
      else
        assert opts[:storage_provider] == storage_provider
      end

      :ok
    end)
  end
end
