defmodule Cache.ApplicationTest do
  use ExUnit.Case, async: true
  use Mimic

  alias Cache.Config

  setup :set_mimic_from_context

  test "starts the key value store before distributed KV supervisor" do
    stub(Config, :analytics_enabled?, fn -> false end)
    stub(Config, :distributed_kv_enabled?, fn -> true end)

    children = Cache.Application.children()

    key_value_store_index = Enum.find_index(children, &(&1 == Cache.KeyValueStore))

    distributed_supervisor_index =
      Enum.find_index(children, fn
        %{id: Cache.DistributedKV.Supervisor} -> true
        _ -> false
      end)

    assert key_value_store_index < distributed_supervisor_index
  end

  test "starts distributed KV supervisor before Oban" do
    stub(Config, :analytics_enabled?, fn -> false end)
    stub(Config, :distributed_kv_enabled?, fn -> true end)

    children = Cache.Application.children()

    distributed_supervisor_index =
      Enum.find_index(children, fn
        %{id: Cache.DistributedKV.Supervisor} -> true
        _ -> false
      end)

    oban_index =
      Enum.find_index(children, fn
        {Oban, _opts} -> true
        _ -> false
      end)

    assert distributed_supervisor_index < oban_index
  end
end
