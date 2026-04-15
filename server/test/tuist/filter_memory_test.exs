defmodule Tuist.FilterMemoryTest do
  use ExUnit.Case, async: true

  alias Tuist.FilterMemory

  setup do
    user_id = System.unique_integer([:positive])
    tab_id = "tab-#{System.unique_integer([:positive])}"
    %{user_id: user_id, tab_id: tab_id}
  end

  describe "get_all/2" do
    test "returns empty map when no entries exist", %{user_id: user_id, tab_id: tab_id} do
      assert FilterMemory.get_all(user_id, tab_id) == %{}
    end

    test "returns empty map when tab_id is missing", %{user_id: user_id} do
      assert FilterMemory.get_all(user_id, nil) == %{}
      assert FilterMemory.get_all(user_id, "") == %{}
    end

    test "returns empty map when user_id is nil", %{tab_id: tab_id} do
      assert FilterMemory.get_all(nil, tab_id) == %{}
    end
  end

  describe "put/4 + get_all/2" do
    test "round-trips a single entry", %{user_id: user_id, tab_id: tab_id} do
      :ok = FilterMemory.put(user_id, tab_id, "builds", "scheme=App")

      assert FilterMemory.get_all(user_id, tab_id) == %{"builds" => "scheme=App"}
    end

    test "merges multiple routes", %{user_id: user_id, tab_id: tab_id} do
      :ok = FilterMemory.put(user_id, tab_id, "builds", "scheme=App")
      :ok = FilterMemory.put(user_id, tab_id, "build-runs", "ran_by=user")

      assert FilterMemory.get_all(user_id, tab_id) == %{
               "builds" => "scheme=App",
               "build-runs" => "ran_by=user"
             }
    end

    test "overwrites an existing route's query", %{user_id: user_id, tab_id: tab_id} do
      :ok = FilterMemory.put(user_id, tab_id, "builds", "scheme=App")
      :ok = FilterMemory.put(user_id, tab_id, "builds", "scheme=Other")

      assert FilterMemory.get_all(user_id, tab_id) == %{"builds" => "scheme=Other"}
    end

    test "normalizes a nil query to empty string", %{user_id: user_id, tab_id: tab_id} do
      :ok = FilterMemory.put(user_id, tab_id, "builds", nil)

      assert FilterMemory.get_all(user_id, tab_id) == %{"builds" => ""}
    end

    test "isolates different tabs under the same user", %{user_id: user_id} do
      tab_a = "tab-a-#{System.unique_integer([:positive])}"
      tab_b = "tab-b-#{System.unique_integer([:positive])}"

      :ok = FilterMemory.put(user_id, tab_a, "builds", "scheme=App")
      :ok = FilterMemory.put(user_id, tab_b, "builds", "scheme=Other")

      assert FilterMemory.get_all(user_id, tab_a) == %{"builds" => "scheme=App"}
      assert FilterMemory.get_all(user_id, tab_b) == %{"builds" => "scheme=Other"}
    end

    test "isolates different users on the same tab id" do
      tab_id = "shared-#{System.unique_integer([:positive])}"
      user_a = System.unique_integer([:positive])
      user_b = System.unique_integer([:positive])

      :ok = FilterMemory.put(user_a, tab_id, "builds", "scheme=A")
      :ok = FilterMemory.put(user_b, tab_id, "builds", "scheme=B")

      assert FilterMemory.get_all(user_a, tab_id) == %{"builds" => "scheme=A"}
      assert FilterMemory.get_all(user_b, tab_id) == %{"builds" => "scheme=B"}
    end

    test "is a no-op with a missing tab_id", %{user_id: user_id} do
      assert :ok = FilterMemory.put(user_id, nil, "builds", "x=1")
      assert :ok = FilterMemory.put(user_id, "", "builds", "x=1")
    end

    test "is a no-op with a nil user_id", %{tab_id: tab_id} do
      assert :ok = FilterMemory.put(nil, tab_id, "builds", "x=1")
      assert FilterMemory.get_all(nil, tab_id) == %{}
    end
  end
end
