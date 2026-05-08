defmodule Tuist.ClickHouseRetryTest do
  use ExUnit.Case, async: true

  import ExUnit.CaptureLog

  alias Tuist.ClickHouseRetry

  describe "run/1" do
    test "returns the function result on success without retrying" do
      counter = :counters.new(1, [])

      result =
        ClickHouseRetry.run(fn ->
          :counters.add(counter, 1, 1)
          :ok
        end)

      assert result == :ok
      assert :counters.get(counter, 1) == 1
    end

    test "retries on Mint.TransportError and returns once the call succeeds" do
      counter = :counters.new(1, [])

      result =
        capture_log(fn ->
          assert ClickHouseRetry.run(fn ->
                   :counters.add(counter, 1, 1)

                   if :counters.get(counter, 1) < 2 do
                     raise %Mint.TransportError{reason: :closed}
                   end

                   :ok
                 end) == :ok
        end)

      assert :counters.get(counter, 1) == 2
      assert result =~ "ClickHouse transport error"
    end

    test "reraises Mint.TransportError after exhausting attempts" do
      counter = :counters.new(1, [])

      capture_log(fn ->
        assert_raise Mint.TransportError, fn ->
          ClickHouseRetry.run(fn ->
            :counters.add(counter, 1, 1)
            raise %Mint.TransportError{reason: :timeout}
          end)
        end
      end)

      assert :counters.get(counter, 1) == 3
    end

    test "lets non-Mint exceptions propagate without retry" do
      counter = :counters.new(1, [])

      assert_raise RuntimeError, fn ->
        ClickHouseRetry.run(fn ->
          :counters.add(counter, 1, 1)
          raise "boom"
        end)
      end

      assert :counters.get(counter, 1) == 1
    end
  end
end
