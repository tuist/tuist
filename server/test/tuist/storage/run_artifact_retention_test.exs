defmodule Tuist.Storage.RunArtifactRetentionTest do
  use ExUnit.Case, async: true
  use Mimic

  alias Tuist.Accounts.Account
  alias Tuist.Billing.Subscription
  alias Tuist.Environment
  alias Tuist.Repo
  alias Tuist.Storage
  alias Tuist.Storage.RunArtifactRetention

  setup :set_mimic_from_context

  describe "delete_expired/1" do
    test "deletes expired run artifacts regardless of which run they belong to" do
      test_run_bundle_key = "tuist/app/runs/018fb6aa-c19d-7829-8ed3-934375dfba53/result_bundle.zip"
      command_event_session_key = "tuist/app/runs/0123456789abcdef0123456789abcdef/session.zip"
      legacy_run_key = "tuist/app/runs/1085251/result_bundle.zip"
      result_bundle_object_key = "tuist/app/runs/018fb6aa-c19d-7829-8ed3-934375dfba53/0~abc.json"
      recent_bundle_key = "tuist/app/runs/019e2c6c-d9ed-7391-8110-2f38ddd27d2c/result_bundle.zip"
      build_key = "tuist/app/builds/018fb6aa-c19d-7829-8ed3-934375dfba53/build.zip"
      test_attachment_key = "tuist/app/tests/runs/018fb6aa-c19d-7829-8ed3-934375dfba53/attachments/1/log.txt"

      expect(Environment, :s3_bucket_name, fn -> "storage-bucket" end)

      expect(Storage, :list_objects_from_bucket, fn "storage-bucket",
                                                    [prefix: "", max_keys: 1000, continuation_token: nil] ->
        {:ok,
         %{
           body: %{
             contents: [
               %{key: test_run_bundle_key, last_modified: days_ago(31)},
               %{key: command_event_session_key, last_modified: days_ago(31)},
               %{key: legacy_run_key, last_modified: days_ago(400)},
               %{key: result_bundle_object_key, last_modified: days_ago(31)},
               %{key: recent_bundle_key, last_modified: days_ago(6)},
               %{key: build_key, last_modified: days_ago(31)},
               %{key: test_attachment_key, last_modified: days_ago(31)}
             ],
             is_truncated: true,
             next_continuation_token: "next-page"
           }
         }}
      end)

      expect_accounts_and_plans([%Account{id: 1, name: "tuist"}])

      expect_delete_objects(
        [test_run_bundle_key, command_event_session_key, legacy_run_key, result_bundle_object_key],
        "storage-bucket"
      )

      assert RunArtifactRetention.delete_expired() == {:ok, "next-page"}
    end

    test "deletes expired run artifacts of accounts that no longer exist" do
      expired_orphan_key = "deleted-account/app/runs/018fb6aa-c19d-7829-8ed3-934375dfba53/result_bundle.zip"
      recent_orphan_key = "deleted-account/app/runs/019e2c6c-d9ed-7391-8110-2f38ddd27d2c/result_bundle.zip"

      expect(Environment, :s3_bucket_name, fn -> "storage-bucket" end)

      expect(Storage, :list_objects_from_bucket, fn "storage-bucket", _opts ->
        {:ok,
         %{
           body: %{
             contents: [
               %{key: expired_orphan_key, last_modified: days_ago(31)},
               %{key: recent_orphan_key, last_modified: days_ago(6)}
             ],
             is_truncated: false
           }
         }}
      end)

      expect(Repo, :all, fn _query -> [] end)
      expect_delete_objects([expired_orphan_key], "storage-bucket")

      assert RunArtifactRetention.delete_expired() == {:ok, nil}
    end

    test "keeps run artifacts for the account plan's window" do
      air_key = "air-account/app/runs/018fb6aa-c19d-7829-8ed3-934375dfba53/result_bundle.zip"
      pro_expired_key = "pro-account/app/runs/018fb6aa-c19d-7829-8ed3-934375dfba53/result_bundle.zip"
      pro_recent_key = "pro-account/app/runs/019e2c6c-d9ed-7391-8110-2f38ddd27d2c/result_bundle.zip"
      enterprise_expired_key = "enterprise-account/app/runs/018fb6aa-c19d-7829-8ed3-934375dfba53/result_bundle.zip"
      enterprise_recent_key = "enterprise-account/app/runs/019e2c6c-d9ed-7391-8110-2f38ddd27d2c/result_bundle.zip"

      expect(Environment, :s3_bucket_name, fn -> "storage-bucket" end)

      expect(Storage, :list_objects_from_bucket, fn "storage-bucket", _opts ->
        {:ok,
         %{
           body: %{
             contents: [
               %{key: air_key, last_modified: days_ago(8)},
               %{key: pro_expired_key, last_modified: days_ago(31)},
               %{key: pro_recent_key, last_modified: days_ago(29)},
               %{key: enterprise_expired_key, last_modified: days_ago(31)},
               %{key: enterprise_recent_key, last_modified: days_ago(29)}
             ],
             is_truncated: false
           }
         }}
      end)

      expect_accounts_and_plans(
        [
          %Account{id: 1, name: "air-account"},
          %Account{id: 2, name: "pro-account"},
          %Account{id: 3, name: "enterprise-account"}
        ],
        %{2 => :pro, 3 => :enterprise}
      )

      expect_delete_objects([air_key, pro_expired_key, enterprise_expired_key], "storage-bucket")

      assert RunArtifactRetention.delete_expired() == {:ok, nil}
    end

    test "resolves run artifacts under a differently cased account handle" do
      mixed_case_key = "TUIST/app/runs/018fb6aa-c19d-7829-8ed3-934375dfba53/result_bundle.zip"

      expect(Environment, :s3_bucket_name, fn -> "storage-bucket" end)

      expect(Storage, :list_objects_from_bucket, fn "storage-bucket", _opts ->
        {:ok, %{body: %{contents: [%{key: mixed_case_key, last_modified: days_ago(31)}], is_truncated: false}}}
      end)

      expect_accounts_and_plans([%Account{id: 1, name: "tuist"}])
      expect_delete_objects([mixed_case_key], "storage-bucket")

      assert RunArtifactRetention.delete_expired() == {:ok, nil}
    end

    test "uses an explicit retention window" do
      expired_key = "tuist/app/runs/018fb6aa-c19d-7829-8ed3-934375dfba53/result_bundle.zip"
      recent_key = "tuist/app/runs/019e2c6c-d9ed-7391-8110-2f38ddd27d2c/result_bundle.zip"

      expect(Environment, :s3_bucket_name, fn -> "storage-bucket" end)

      expect(Storage, :list_objects_from_bucket, fn "storage-bucket", _opts ->
        {:ok,
         %{
           body: %{
             contents: [
               %{key: expired_key, last_modified: days_ago(61)},
               %{key: recent_key, last_modified: days_ago(59)}
             ],
             is_truncated: false
           }
         }}
      end)

      expect_accounts_and_plans([%Account{id: 1, name: "tuist"}])
      expect_delete_objects([expired_key], "storage-bucket")

      assert RunArtifactRetention.delete_expired(retention_days: 60) == {:ok, nil}
    end

    test "skips cleanup when the managed storage bucket is not configured" do
      expect(Environment, :s3_bucket_name, fn -> nil end)

      assert RunArtifactRetention.delete_expired() == :ok
    end

    test "uses the Azure Blob container when Azure Blob is the server artifact provider" do
      expired_key = "tuist/app/runs/018fb6aa-c19d-7829-8ed3-934375dfba53/result_bundle.zip"

      expect(Environment, :object_storage_provider, fn -> :azure_blob end)
      expect(Environment, :azure_blob_container_name, fn -> "azure-artifacts" end)

      expect(Storage, :list_objects_from_bucket, fn "azure-artifacts", opts ->
        assert opts[:storage_provider] == :azure_blob
        {:ok, %{body: %{contents: [%{key: expired_key, last_modified: days_ago(31)}], is_truncated: false}}}
      end)

      expect_accounts_and_plans([%Account{id: 1, name: "tuist"}])
      expect_delete_objects([expired_key], "azure-artifacts", :azure_blob)

      assert RunArtifactRetention.delete_expired() == {:ok, nil}
    end
  end

  defp days_ago(days), do: DateTime.add(DateTime.utc_now(), -days, :day)

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
      if storage_provider == :s3 do
        refute Keyword.has_key?(opts, :storage_provider)
      else
        assert opts[:storage_provider] == storage_provider
      end

      :ok
    end)
  end
end
