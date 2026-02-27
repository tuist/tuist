defmodule Cache.KeyValueStoreTest do
  use ExUnit.Case, async: true
  use Mimic

  import Ecto.Query

  alias Cache.KeyValueBuffer
  alias Cache.KeyValueEntry
  alias Cache.KeyValueEvictionWorker
  alias Cache.KeyValueStore
  alias Cache.Repo
  alias Ecto.Adapters.SQL.Sandbox

  setup :set_mimic_from_context

  setup context do
    :ok = Sandbox.checkout(Repo)

    context = Cache.BufferTestHelpers.setup_key_value_buffer(context)
    suffix = context.unique_suffix

    cache_name = :"kv_cache_test_#{suffix}"
    start_supervised!({Cachex, name: cache_name})

    {:ok,
     Map.merge(context, %{
       cache_name: cache_name,
       account_handle: "test-account-#{suffix}",
       project_handle: "test-project-#{suffix}",
       cas_id: "test_cas_id_#{suffix}"
     })}
  end

  describe "put_key_value/4 and get_key_value/3" do
    test "stores and retrieves a single value", %{
      cache_name: cache_name,
      account_handle: account_handle,
      project_handle: project_handle,
      cas_id: cas_id
    } do
      values = ["value1"]

      assert :ok =
               KeyValueStore.put_key_value(
                 cas_id,
                 account_handle,
                 project_handle,
                 values,
                 cache_name: cache_name
               )

      assert {:ok, json} =
               KeyValueStore.get_key_value(
                 cas_id,
                 account_handle,
                 project_handle,
                 cache_name: cache_name
               )

      decoded = Jason.decode!(json)
      assert decoded["entries"] == [%{"value" => "value1"}]
    end

    test "stores and retrieves multiple values", %{
      cache_name: cache_name,
      account_handle: account_handle,
      project_handle: project_handle,
      cas_id: cas_id
    } do
      values = ["value1", "value2", "value3"]

      assert :ok =
               KeyValueStore.put_key_value(
                 cas_id,
                 account_handle,
                 project_handle,
                 values,
                 cache_name: cache_name
               )

      assert {:ok, json} =
               KeyValueStore.get_key_value(
                 cas_id,
                 account_handle,
                 project_handle,
                 cache_name: cache_name
               )

      decoded = Jason.decode!(json)

      assert decoded["entries"] == [
               %{"value" => "value1"},
               %{"value" => "value2"},
               %{"value" => "value3"}
             ]
    end

    test "returns pre-encoded JSON without re-encoding", %{
      cache_name: cache_name,
      account_handle: account_handle,
      project_handle: project_handle,
      cas_id: cas_id
    } do
      values = ["test_value"]

      assert :ok =
               KeyValueStore.put_key_value(
                 cas_id,
                 account_handle,
                 project_handle,
                 values,
                 cache_name: cache_name
               )

      assert {:ok, json} =
               KeyValueStore.get_key_value(
                 cas_id,
                 account_handle,
                 project_handle,
                 cache_name: cache_name
               )

      assert is_binary(json)
      assert {:ok, _} = Jason.decode(json)
    end

    test "overwrites existing values for the same key", %{
      cache_name: cache_name,
      account_handle: account_handle,
      project_handle: project_handle,
      cas_id: cas_id
    } do
      initial_values = ["initial1", "initial2"]
      updated_values = ["updated1", "updated2", "updated3"]

      assert :ok =
               KeyValueStore.put_key_value(
                 cas_id,
                 account_handle,
                 project_handle,
                 initial_values,
                 cache_name: cache_name
               )

      assert :ok =
               KeyValueStore.put_key_value(
                 cas_id,
                 account_handle,
                 project_handle,
                 updated_values,
                 cache_name: cache_name
               )

      assert {:ok, json} =
               KeyValueStore.get_key_value(
                 cas_id,
                 account_handle,
                 project_handle,
                 cache_name: cache_name
               )

      decoded = Jason.decode!(json)

      assert decoded["entries"] == [
               %{"value" => "updated1"},
               %{"value" => "updated2"},
               %{"value" => "updated3"}
             ]
    end

    test "stores values separately for different CAS IDs", %{
      cache_name: cache_name,
      account_handle: account_handle,
      project_handle: project_handle,
      cas_id: cas_id
    } do
      cas_id_1 = "#{cas_id}-1"
      cas_id_2 = "#{cas_id}-2"
      values_1 = ["value_for_cas_1"]
      values_2 = ["value_for_cas_2"]

      assert :ok =
               KeyValueStore.put_key_value(
                 cas_id_1,
                 account_handle,
                 project_handle,
                 values_1,
                 cache_name: cache_name
               )

      assert :ok =
               KeyValueStore.put_key_value(
                 cas_id_2,
                 account_handle,
                 project_handle,
                 values_2,
                 cache_name: cache_name
               )

      assert {:ok, json_1} =
               KeyValueStore.get_key_value(
                 cas_id_1,
                 account_handle,
                 project_handle,
                 cache_name: cache_name
               )

      assert {:ok, json_2} =
               KeyValueStore.get_key_value(
                 cas_id_2,
                 account_handle,
                 project_handle,
                 cache_name: cache_name
               )

      decoded_1 = Jason.decode!(json_1)
      decoded_2 = Jason.decode!(json_2)

      assert decoded_1["entries"] == [%{"value" => "value_for_cas_1"}]
      assert decoded_2["entries"] == [%{"value" => "value_for_cas_2"}]
    end

    test "stores values separately for different accounts", %{
      cache_name: cache_name,
      account_handle: account_handle,
      project_handle: project_handle,
      cas_id: cas_id
    } do
      account_1 = "#{account_handle}-1"
      account_2 = "#{account_handle}-2"
      values_1 = ["value_for_account_1"]
      values_2 = ["value_for_account_2"]

      assert :ok =
               KeyValueStore.put_key_value(
                 cas_id,
                 account_1,
                 project_handle,
                 values_1,
                 cache_name: cache_name
               )

      assert :ok =
               KeyValueStore.put_key_value(
                 cas_id,
                 account_2,
                 project_handle,
                 values_2,
                 cache_name: cache_name
               )

      assert {:ok, json_1} =
               KeyValueStore.get_key_value(
                 cas_id,
                 account_1,
                 project_handle,
                 cache_name: cache_name
               )

      assert {:ok, json_2} =
               KeyValueStore.get_key_value(
                 cas_id,
                 account_2,
                 project_handle,
                 cache_name: cache_name
               )

      decoded_1 = Jason.decode!(json_1)
      decoded_2 = Jason.decode!(json_2)

      assert decoded_1["entries"] == [%{"value" => "value_for_account_1"}]
      assert decoded_2["entries"] == [%{"value" => "value_for_account_2"}]
    end

    test "stores values separately for different projects", %{
      cache_name: cache_name,
      account_handle: account_handle,
      project_handle: project_handle,
      cas_id: cas_id
    } do
      project_1 = "#{project_handle}-1"
      project_2 = "#{project_handle}-2"
      values_1 = ["value_for_project_1"]
      values_2 = ["value_for_project_2"]

      assert :ok =
               KeyValueStore.put_key_value(
                 cas_id,
                 account_handle,
                 project_1,
                 values_1,
                 cache_name: cache_name
               )

      assert :ok =
               KeyValueStore.put_key_value(
                 cas_id,
                 account_handle,
                 project_2,
                 values_2,
                 cache_name: cache_name
               )

      assert {:ok, json_1} =
               KeyValueStore.get_key_value(
                 cas_id,
                 account_handle,
                 project_1,
                 cache_name: cache_name
               )

      assert {:ok, json_2} =
               KeyValueStore.get_key_value(
                 cas_id,
                 account_handle,
                 project_2,
                 cache_name: cache_name
               )

      decoded_1 = Jason.decode!(json_1)
      decoded_2 = Jason.decode!(json_2)

      assert decoded_1["entries"] == [%{"value" => "value_for_project_1"}]
      assert decoded_2["entries"] == [%{"value" => "value_for_project_2"}]
    end

    test "handles empty values list", %{
      cache_name: cache_name,
      account_handle: account_handle,
      project_handle: project_handle,
      cas_id: cas_id
    } do
      values = []

      assert :ok =
               KeyValueStore.put_key_value(
                 cas_id,
                 account_handle,
                 project_handle,
                 values,
                 cache_name: cache_name
               )

      assert {:ok, json} =
               KeyValueStore.get_key_value(
                 cas_id,
                 account_handle,
                 project_handle,
                 cache_name: cache_name
               )

      decoded = Jason.decode!(json)
      assert decoded["entries"] == []
    end

    test "handles values with special characters", %{
      cache_name: cache_name,
      account_handle: account_handle,
      project_handle: project_handle,
      cas_id: cas_id
    } do
      values = [
        "value with spaces",
        "value/with/slashes",
        "value:with:colons",
        "value@with@symbols",
        "value\nwith\nnewlines"
      ]

      assert :ok =
               KeyValueStore.put_key_value(
                 cas_id,
                 account_handle,
                 project_handle,
                 values,
                 cache_name: cache_name
               )

      assert {:ok, json} =
               KeyValueStore.get_key_value(
                 cas_id,
                 account_handle,
                 project_handle,
                 cache_name: cache_name
               )

      decoded = Jason.decode!(json)

      assert decoded["entries"] == [
               %{"value" => "value with spaces"},
               %{"value" => "value/with/slashes"},
               %{"value" => "value:with:colons"},
               %{"value" => "value@with@symbols"},
               %{"value" => "value\nwith\nnewlines"}
             ]
    end
  end

  describe "get_key_value/3" do
    test "returns {:error, :not_found} when no entry exists", %{
      cache_name: cache_name,
      account_handle: account_handle,
      project_handle: project_handle,
      cas_id: cas_id
    } do
      assert {:error, :not_found} =
               KeyValueStore.get_key_value(
                 "#{cas_id}-missing",
                 account_handle,
                 project_handle,
                 cache_name: cache_name
               )
    end

    test "returns {:error, :not_found} for nonexistent account", %{
      cache_name: cache_name,
      account_handle: account_handle,
      project_handle: project_handle,
      cas_id: cas_id
    } do
      values = ["test_value"]

      assert :ok =
               KeyValueStore.put_key_value(
                 cas_id,
                 account_handle,
                 project_handle,
                 values,
                 cache_name: cache_name
               )

      assert {:error, :not_found} =
               KeyValueStore.get_key_value(
                 cas_id,
                 "nonexistent_account",
                 project_handle,
                 cache_name: cache_name
               )
    end

    test "returns {:error, :not_found} for nonexistent project", %{
      cache_name: cache_name,
      account_handle: account_handle,
      project_handle: project_handle,
      cas_id: cas_id
    } do
      values = ["test_value"]

      assert :ok =
               KeyValueStore.put_key_value(
                 cas_id,
                 account_handle,
                 project_handle,
                 values,
                 cache_name: cache_name
               )

      assert {:error, :not_found} =
               KeyValueStore.get_key_value(
                 cas_id,
                 account_handle,
                 "nonexistent_project",
                 cache_name: cache_name
               )
    end
  end

  describe "persistence" do
    test "persists entries to sqlite", %{
      cache_name: cache_name,
      account_handle: account_handle,
      project_handle: project_handle,
      cas_id: cas_id
    } do
      values = ["value1", "value2"]

      assert :ok =
               KeyValueStore.put_key_value(
                 cas_id,
                 account_handle,
                 project_handle,
                 values,
                 cache_name: cache_name
               )

      :ok = KeyValueBuffer.flush()

      key = "keyvalue:#{account_handle}:#{project_handle}:#{cas_id}"
      record = Repo.get_by!(KeyValueEntry, key: key)
      assert record.json_payload == Jason.encode!(%{entries: [%{"value" => "value1"}, %{"value" => "value2"}]})
    end

    test "reads through cachex when entries exist only in sqlite", %{
      cache_name: cache_name,
      account_handle: account_handle,
      project_handle: project_handle,
      cas_id: cas_id
    } do
      values = ["value1", "value2"]

      assert :ok =
               KeyValueStore.put_key_value(
                 cas_id,
                 account_handle,
                 project_handle,
                 values,
                 cache_name: cache_name
               )

      :ok = KeyValueBuffer.flush()
      Cachex.clear(cache_name)

      assert {:ok, json} =
               KeyValueStore.get_key_value(
                 cas_id,
                 account_handle,
                 project_handle,
                 cache_name: cache_name
               )

      assert Jason.decode!(json)["entries"] == [%{"value" => "value1"}, %{"value" => "value2"}]

      key = "keyvalue:#{account_handle}:#{project_handle}:#{cas_id}"
      assert {:ok, ^json} = Cachex.get(cache_name, key)
    end
  end

  describe "access tracking" do
    test "SQLite fallback read updates last_accessed_at", %{
      cache_name: cache_name,
      account_handle: account_handle,
      project_handle: project_handle,
      cas_id: cas_id
    } do
      values = ["value1"]

      assert :ok =
               KeyValueStore.put_key_value(
                 cas_id,
                 account_handle,
                 project_handle,
                 values,
                 cache_name: cache_name
               )

      :ok = KeyValueBuffer.flush()

      key = "keyvalue:#{account_handle}:#{project_handle}:#{cas_id}"
      old_time = DateTime.add(DateTime.utc_now(), -120, :second)

      Repo.update_all(
        from(e in KeyValueEntry, where: e.key == ^key),
        set: [last_accessed_at: old_time]
      )

      Cachex.clear(cache_name)

      assert {:ok, _json} =
               KeyValueStore.get_key_value(
                 cas_id,
                 account_handle,
                 project_handle,
                 cache_name: cache_name
               )

      :ok = KeyValueBuffer.flush()

      record = Repo.get_by!(KeyValueEntry, key: key)
      assert DateTime.after?(record.last_accessed_at, old_time)
    end

    test "Cachex hit does not update last_accessed_at", %{
      cache_name: cache_name,
      account_handle: account_handle,
      project_handle: project_handle,
      cas_id: cas_id
    } do
      values = ["value1"]

      assert :ok =
               KeyValueStore.put_key_value(
                 cas_id,
                 account_handle,
                 project_handle,
                 values,
                 cache_name: cache_name
               )

      :ok = KeyValueBuffer.flush()

      key = "keyvalue:#{account_handle}:#{project_handle}:#{cas_id}"
      old_time = DateTime.add(DateTime.utc_now(), -120, :second)

      Repo.update_all(
        from(e in KeyValueEntry, where: e.key == ^key),
        set: [last_accessed_at: old_time]
      )

      assert {:ok, _json} =
               KeyValueStore.get_key_value(
                 cas_id,
                 account_handle,
                 project_handle,
                 cache_name: cache_name
               )

      :ok = KeyValueBuffer.flush()

      record = Repo.get_by!(KeyValueEntry, key: key)

      assert DateTime.truncate(record.last_accessed_at, :second) ==
               DateTime.truncate(old_time, :second)
    end

    test "full lifecycle: write, expire from Cachex, read, evict", %{
      cache_name: cache_name,
      account_handle: account_handle,
      project_handle: project_handle,
      cas_id: cas_id
    } do
      values = ["value1"]

      assert :ok =
               KeyValueStore.put_key_value(
                 cas_id,
                 account_handle,
                 project_handle,
                 values,
                 cache_name: cache_name
               )

      :ok = KeyValueBuffer.flush()

      key = "keyvalue:#{account_handle}:#{project_handle}:#{cas_id}"
      record = Repo.get_by!(KeyValueEntry, key: key)
      assert record.last_accessed_at

      Cachex.clear(cache_name)

      assert {:ok, _json} =
               KeyValueStore.get_key_value(
                 cas_id,
                 account_handle,
                 project_handle,
                 cache_name: cache_name
               )

      :ok = KeyValueBuffer.flush()

      updated_record = Repo.get_by!(KeyValueEntry, key: key)
      assert DateTime.compare(updated_record.last_accessed_at, record.last_accessed_at) != :lt

      old_time = DateTime.add(DateTime.utc_now(), -31, :day)

      Repo.update_all(
        from(e in KeyValueEntry, where: e.key == ^key),
        set: [last_accessed_at: old_time]
      )

      KeyValueEvictionWorker.perform(%Oban.Job{})

      assert Repo.get_by(KeyValueEntry, key: key) == nil
    end
  end
end
