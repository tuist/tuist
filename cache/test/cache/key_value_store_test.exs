defmodule Cache.KeyValueStoreTest do
  use ExUnit.Case, async: false

  alias Cache.KeyValueEntry
  alias Cache.KeyValueStore
  alias Cache.Repo
  alias Ecto.Adapters.SQL.Sandbox

  @account_handle "test-account"
  @project_handle "test-project"
  @cas_id "test_cas_id_123"

  setup do
    :ok = Sandbox.checkout(Repo)
    Sandbox.mode(Repo, {:shared, self()})
    Cachex.clear(:cache_keyvalue_store)
    :ok
  end

  describe "put_key_value/4 and get_key_value/3" do
    test "stores and retrieves a single value" do
      values = ["value1"]

      assert :ok = KeyValueStore.put_key_value(@cas_id, @account_handle, @project_handle, values)

      assert {:ok, json} = KeyValueStore.get_key_value(@cas_id, @account_handle, @project_handle)

      decoded = Jason.decode!(json)
      assert decoded["entries"] == [%{"value" => "value1"}]
    end

    test "stores and retrieves multiple values" do
      values = ["value1", "value2", "value3"]

      assert :ok = KeyValueStore.put_key_value(@cas_id, @account_handle, @project_handle, values)

      assert {:ok, json} = KeyValueStore.get_key_value(@cas_id, @account_handle, @project_handle)

      decoded = Jason.decode!(json)

      assert decoded["entries"] == [
               %{"value" => "value1"},
               %{"value" => "value2"},
               %{"value" => "value3"}
             ]
    end

    test "returns pre-encoded JSON without re-encoding" do
      values = ["test_value"]

      assert :ok = KeyValueStore.put_key_value(@cas_id, @account_handle, @project_handle, values)

      assert {:ok, json} = KeyValueStore.get_key_value(@cas_id, @account_handle, @project_handle)

      # JSON should be a string, not a map
      assert is_binary(json)
      # Should be valid JSON
      assert {:ok, _} = Jason.decode(json)
    end

    test "overwrites existing values for the same key" do
      initial_values = ["initial1", "initial2"]
      updated_values = ["updated1", "updated2", "updated3"]

      assert :ok =
               KeyValueStore.put_key_value(
                 @cas_id,
                 @account_handle,
                 @project_handle,
                 initial_values
               )

      assert :ok =
               KeyValueStore.put_key_value(
                 @cas_id,
                 @account_handle,
                 @project_handle,
                 updated_values
               )

      assert {:ok, json} = KeyValueStore.get_key_value(@cas_id, @account_handle, @project_handle)

      decoded = Jason.decode!(json)

      assert decoded["entries"] == [
               %{"value" => "updated1"},
               %{"value" => "updated2"},
               %{"value" => "updated3"}
             ]
    end

    test "stores values separately for different CAS IDs" do
      cas_id_1 = "cas_id_1"
      cas_id_2 = "cas_id_2"
      values_1 = ["value_for_cas_1"]
      values_2 = ["value_for_cas_2"]

      assert :ok =
               KeyValueStore.put_key_value(cas_id_1, @account_handle, @project_handle, values_1)

      assert :ok =
               KeyValueStore.put_key_value(cas_id_2, @account_handle, @project_handle, values_2)

      assert {:ok, json_1} =
               KeyValueStore.get_key_value(cas_id_1, @account_handle, @project_handle)

      assert {:ok, json_2} =
               KeyValueStore.get_key_value(cas_id_2, @account_handle, @project_handle)

      decoded_1 = Jason.decode!(json_1)
      decoded_2 = Jason.decode!(json_2)

      assert decoded_1["entries"] == [%{"value" => "value_for_cas_1"}]
      assert decoded_2["entries"] == [%{"value" => "value_for_cas_2"}]
    end

    test "stores values separately for different accounts" do
      account_1 = "account-1"
      account_2 = "account-2"
      values_1 = ["value_for_account_1"]
      values_2 = ["value_for_account_2"]

      assert :ok = KeyValueStore.put_key_value(@cas_id, account_1, @project_handle, values_1)
      assert :ok = KeyValueStore.put_key_value(@cas_id, account_2, @project_handle, values_2)

      assert {:ok, json_1} = KeyValueStore.get_key_value(@cas_id, account_1, @project_handle)
      assert {:ok, json_2} = KeyValueStore.get_key_value(@cas_id, account_2, @project_handle)

      decoded_1 = Jason.decode!(json_1)
      decoded_2 = Jason.decode!(json_2)

      assert decoded_1["entries"] == [%{"value" => "value_for_account_1"}]
      assert decoded_2["entries"] == [%{"value" => "value_for_account_2"}]
    end

    test "stores values separately for different projects" do
      project_1 = "project-1"
      project_2 = "project-2"
      values_1 = ["value_for_project_1"]
      values_2 = ["value_for_project_2"]

      assert :ok = KeyValueStore.put_key_value(@cas_id, @account_handle, project_1, values_1)
      assert :ok = KeyValueStore.put_key_value(@cas_id, @account_handle, project_2, values_2)

      assert {:ok, json_1} = KeyValueStore.get_key_value(@cas_id, @account_handle, project_1)
      assert {:ok, json_2} = KeyValueStore.get_key_value(@cas_id, @account_handle, project_2)

      decoded_1 = Jason.decode!(json_1)
      decoded_2 = Jason.decode!(json_2)

      assert decoded_1["entries"] == [%{"value" => "value_for_project_1"}]
      assert decoded_2["entries"] == [%{"value" => "value_for_project_2"}]
    end

    test "handles empty values list" do
      values = []

      assert :ok = KeyValueStore.put_key_value(@cas_id, @account_handle, @project_handle, values)

      assert {:ok, json} = KeyValueStore.get_key_value(@cas_id, @account_handle, @project_handle)

      decoded = Jason.decode!(json)
      assert decoded["entries"] == []
    end

    test "handles values with special characters" do
      values = [
        "value with spaces",
        "value/with/slashes",
        "value:with:colons",
        "value@with@symbols",
        "value\nwith\nnewlines"
      ]

      assert :ok = KeyValueStore.put_key_value(@cas_id, @account_handle, @project_handle, values)

      assert {:ok, json} = KeyValueStore.get_key_value(@cas_id, @account_handle, @project_handle)

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
    test "returns {:error, :not_found} when no entry exists" do
      assert {:error, :not_found} =
               KeyValueStore.get_key_value("nonexistent_cas_id", @account_handle, @project_handle)
    end

    test "returns {:error, :not_found} for nonexistent account" do
      values = ["test_value"]

      assert :ok = KeyValueStore.put_key_value(@cas_id, @account_handle, @project_handle, values)

      assert {:error, :not_found} =
               KeyValueStore.get_key_value(@cas_id, "nonexistent_account", @project_handle)
    end

    test "returns {:error, :not_found} for nonexistent project" do
      values = ["test_value"]

      assert :ok = KeyValueStore.put_key_value(@cas_id, @account_handle, @project_handle, values)

      assert {:error, :not_found} =
               KeyValueStore.get_key_value(@cas_id, @account_handle, "nonexistent_project")
    end
  end

  describe "persistence" do
    test "persists entries to sqlite" do
      values = ["value1", "value2"]

      assert :ok = KeyValueStore.put_key_value(@cas_id, @account_handle, @project_handle, values)

      key = "keyvalue:#{@account_handle}:#{@project_handle}:#{@cas_id}"
      record = Repo.get_by!(KeyValueEntry, key: key)
      assert record.json_payload == Jason.encode!(%{entries: [%{"value" => "value1"}, %{"value" => "value2"}]})
    end

    test "reads through cachex when entries exist only in sqlite" do
      values = ["value1", "value2"]
      assert :ok = KeyValueStore.put_key_value(@cas_id, @account_handle, @project_handle, values)

      # Simulate cache eviction to force DB lookup
      Cachex.clear(:cache_keyvalue_store)

      assert {:ok, json} = KeyValueStore.get_key_value(@cas_id, @account_handle, @project_handle)
      assert Jason.decode!(json)["entries"] == [%{"value" => "value1"}, %{"value" => "value2"}]

      key = "keyvalue:#{@account_handle}:#{@project_handle}:#{@cas_id}"
      assert {:ok, ^json} = Cachex.get(:cache_keyvalue_store, key)
    end
  end
end
