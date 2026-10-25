defmodule TuistEx.Cache.PlanTest do
  use ExUnit.Case, async: true

  alias TuistEx.Cache.Plan

  test "lookup entries are scoped to a preparation and context" do
    compute = fn -> make_ref() end

    Plan.with_plan(fn ->
      Plan.in_context(:first, fn ->
        first = Plan.fetch(:input, compute)
        assert Plan.fetch(:input, compute) == first
        Plan.in_context(:second, fn -> refute Plan.fetch(:input, compute) == first end)
      end)
    end)

    refute Plan.fetch(:input, compute) == Plan.fetch(:input, compute)
  end

  test "fresh validation cannot read or populate the lookup memo" do
    Plan.with_plan(fn ->
      lookup = Plan.fetch(:input, fn -> :lookup end)
      assert lookup == :lookup
      assert Plan.fresh(fn -> Plan.fetch(:input, fn -> :actual end) end) == :actual
      assert Plan.fetch(:input, fn -> flunk("lost lookup memo") end) == :lookup
    end)
  end

  test "nested fetches retain their entries" do
    Plan.with_plan(fn ->
      Plan.fetch(:outer, fn -> Plan.fetch(:inner, fn -> :value end) end)
      assert Plan.fetch(:inner, fn -> flunk("lost nested memo") end) == :value
    end)
  end

  test "restoration invalidates only the installed application's records" do
    Plan.with_plan(fn ->
      producer = %Mix.Dep{app: :producer}
      consumer = %Mix.Dep{app: :consumer}
      Plan.fetch({:artifacts, producer}, fn -> :old end)
      Plan.fetch({:source, producer}, fn -> :old end)
      Plan.fetch({:source, consumer}, fn -> :keep end)
      Plan.invalidate(:producer)
      assert Plan.fetch({:artifacts, producer}, fn -> :new end) == :new
      assert Plan.fetch({:source, producer}, fn -> :new end) == :new

      assert Plan.fetch({:source, consumer}, fn -> flunk("invalidated another application") end) ==
               :keep

      Plan.clear()
      assert Plan.fetch({:source, consumer}, fn -> :fresh end) == :fresh
    end)
  end

  test "exceptions clean up both validation and preparation frames" do
    assert_raise RuntimeError, fn ->
      Plan.with_plan(fn ->
        Plan.fetch(:input, fn -> :lookup end)
        assert_raise RuntimeError, fn -> Plan.fresh(fn -> raise "validation" end) end
        assert Plan.fetch(:input, fn -> flunk("lost frame") end) == :lookup
        raise "compile"
      end)
    end

    assert Plan.fetch(:input, fn -> :fresh end) == :fresh
  end
end
