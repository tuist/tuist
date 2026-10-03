defmodule Atlas.HTTPTest do
  use ExUnit.Case, async: true

  alias Atlas.HTTP

  test "builds Req defaults from Atlas HTTP config" do
    assert [finch: Atlas.Finch, pool_timeout: 10_000] = HTTP.req_default_options()
  end

  test "builds a Finch child spec from overrides" do
    config = [
      finch_name: Atlas.CustomFinch,
      finch_pools: %{
        default: [
          protocols: [:http1],
          size: 120,
          count: 2,
          pool_max_idle_time: 30_000
        ]
      }
    ]

    assert {Finch, name: Atlas.CustomFinch, pools: %{default: pool_options}} = HTTP.finch_child_spec(config)
    assert Keyword.get(pool_options, :size) == 120
    assert Keyword.get(pool_options, :count) == 2
    assert Keyword.get(pool_options, :pool_max_idle_time) == 30_000
  end

  test "configures Req default options" do
    test_pid = self()

    assert :ok =
             HTTP.configure_req_defaults(
               [finch_name: Atlas.TestFinch, pool_timeout: 12_000],
               fn options ->
                 send(test_pid, {:configured_req_defaults, options})
                 :ok
               end
             )

    assert_receive {:configured_req_defaults, [finch: Atlas.TestFinch, pool_timeout: 12_000]}
  end
end
