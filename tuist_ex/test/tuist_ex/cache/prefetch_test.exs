defmodule TuistEx.Cache.PrefetchTest do
  use ExUnit.Case, async: true

  import Mimic

  alias TuistEx.Cache.Prefetch
  alias TuistEx.Cache.Reapi

  test "a window is acquired once and only reused for the exact input key" do
    expect(Reapi, :get_many, fn :session, [{"first", :first}, {"old", :second}] ->
      %{{"first", :first} => {:ok, "first artifact"}, {"old", :second} => {:ok, "stale artifact"}}
    end)

    expect(Reapi, :get_many, fn :session, [{"new", :second}] ->
      %{{"new", :second} => {:ok, "fresh artifact"}}
    end)

    plan = fn
      "first", %{app: :first} -> [{"first", :first}, {"old", :second}]
      "new", %{app: :second} -> [{"new", :second}]
    end

    Prefetch.with_fetcher(fn -> :session end, plan, fn fetch ->
      assert {:ok, "first artifact"} = fetch.("first", %{app: :first})
      assert {:ok, "fresh artifact"} = fetch.("new", %{app: :second})
    end)
  end

  test "prefetched siblings do not trigger another request or session lookup" do
    expect(Reapi, :get_many, fn :session, requests ->
      Map.new(requests, &{&1, {:ok, elem(&1, 0)}})
    end)

    owner = self()

    remote = fn ->
      send(owner, :opened)
      :session
    end

    Prefetch.with_fetcher(
      remote,
      fn _, _ -> [{"first", :first}, {"second", :second}] end,
      fn fetch ->
        assert {:ok, "first"} = fetch.("first", %{app: :first})
        assert {:ok, "second"} = fetch.("second", %{app: :second})
      end
    )

    assert_receive :opened
    refute_receive :opened
  end

  test "unavailable sessions skip planning and cleanup survives compiler exceptions" do
    keys = MapSet.new(Process.get_keys())

    assert_raise RuntimeError, "compiler failure", fn ->
      Prefetch.with_fetcher(
        fn -> nil end,
        fn _, _ -> flunk("planned without a session") end,
        fn fetch ->
          assert :miss = fetch.("key", %{app: :dependency})
          raise "compiler failure"
        end
      )
    end

    assert MapSet.new(Process.get_keys()) == keys
  end
end
