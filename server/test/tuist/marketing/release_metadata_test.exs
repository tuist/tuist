defmodule Tuist.Marketing.ReleaseMetadataTest do
  use ExUnit.Case, async: true
  use Mimic

  alias OpenTelemetry.Ctx
  alias Tuist.KeyValueStore
  alias Tuist.Marketing.ReleaseMetadata

  test "cache-miss workers inherit and restore the caller's telemetry context" do
    context = Ctx.set_value(Ctx.new(), :release_lookup_test, :caller)
    token = Ctx.attach(context)
    on_exit(fn -> Ctx.detach(token) end)

    expect(KeyValueStore, :get_or_update, fn :key, [ttl: 100], fetch ->
      fn ->
        before = Ctx.get_current()
        result = fetch.()
        assert Ctx.get_current() == before
        result
      end
      |> Task.async()
      |> Task.await()
    end)

    assert :release ==
             ReleaseMetadata.get_or_update(:github, :key, [ttl: 100], fn ->
               assert Ctx.get_value(:release_lookup_test, nil) == :caller
               :release
             end)
  end

  test "cache hits preserve results without invoking the fetch and failures restore context" do
    expect(KeyValueStore, :get_or_update, fn :key, [], _fetch -> :cached end)
    assert :cached == ReleaseMetadata.get_or_update(:app_store, :key, [], fn -> flunk("unexpected fetch") end)

    expect(KeyValueStore, :get_or_update, fn :key, [], fetch ->
      fn ->
        before = Ctx.get_current()
        assert_raise RuntimeError, "failure", fetch
        assert Ctx.get_current() == before
        :failed
      end
      |> Task.async()
      |> Task.await()
    end)

    assert :failed == ReleaseMetadata.get_or_update(:app_store, :key, [], fn -> raise "failure" end)
  end
end
