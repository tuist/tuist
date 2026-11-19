defmodule Tuist.Application.FinchPoolsTest do
  use ExUnit.Case, async: true

  alias Tuist.Application.FinchPools

  describe "default_pool_size/2" do
    test "sizes the paused xcresult queue before the drain monitor resumes it" do
      queues = [process_xcresult: [limit: 4, paused: true]]

      assert FinchPools.default_pool_size(queues, 10) == 64
    end

    test "preserves integer queue configurations" do
      assert FinchPools.default_pool_size([process_xcresult: 4], 10) == 64
      assert FinchPools.default_pool_size([process_build: 2, process_xcresult: 3], 10) == 80
    end

    test "combines integer and keyword download queues without counting unrelated queues" do
      queues = [
        process_build: 2,
        process_xcresult: [paused: false, limit: 3],
        default: 100,
        swift_registry_sync: [limit: 100]
      ]

      assert FinchPools.default_pool_size(queues, 10) == 80
    end

    test "keeps the configured pool size as a floor" do
      assert FinchPools.default_pool_size([process_xcresult: [limit: 4, paused: true]], 500) == 500
    end

    test "preserves the minimum when download queues are absent or disabled" do
      for queues <- [nil, false, [], [default: 100]] do
        assert FinchPools.default_pool_size(queues, 1) == 10
        assert FinchPools.default_pool_size(queues, 500) == 500
      end
    end

    test "does not silently undersize a queue whose keyword config is missing its limit" do
      assert_raise KeyError, fn ->
        FinchPools.default_pool_size([process_xcresult: [paused: true]], 10)
      end
    end
  end
end
