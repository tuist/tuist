defmodule Cache.ApplicationTest do
  use ExUnit.Case, async: true
  use Mimic

  alias Cache.Config

  setup :set_mimic_from_context

  test "starts the key value store before distributed replication workers" do
    stub(Config, :analytics_enabled?, fn -> false end)
    stub(Config, :distributed_kv_enabled?, fn -> true end)

    children = Cache.Application.children()

    key_value_store_index = Enum.find_index(children, &(&1 == Cache.KeyValueStore))
    shipper_index = Enum.find_index(children, &(&1 == Cache.KeyValueReplicationShipper))
    poller_index = Enum.find_index(children, &(&1 == Cache.KeyValueReplicationPoller))

    assert key_value_store_index < shipper_index
    assert key_value_store_index < poller_index
  end
end
