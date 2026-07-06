defmodule Tuist.ClickHouseRetryTest do
  use ExUnit.Case, async: true

  import ExUnit.CaptureLog

  alias Tuist.ClickHouseRetry

  describe "with_retry/1" do
    test "returns the function result on success without retrying" do
      counter = :counters.new(1, [])

      result =
        ClickHouseRetry.with_retry(fn ->
          :counters.add(counter, 1, 1)
          :ok
        end)

      assert result == :ok
      assert :counters.get(counter, 1) == 1
    end

    test "retries on Mint.TransportError and returns once the call succeeds" do
      counter = :counters.new(1, [])

      log =
        capture_log(fn ->
          assert ClickHouseRetry.with_retry(fn ->
                   :counters.add(counter, 1, 1)

                   if :counters.get(counter, 1) < 2 do
                     raise %Mint.TransportError{reason: :closed}
                   end

                   :ok
                 end) == :ok
        end)

      assert :counters.get(counter, 1) == 2
      assert log =~ "ClickHouse operation failed"
    end

    test "retries on DBConnection.ConnectionError" do
      counter = :counters.new(1, [])

      capture_log(fn ->
        assert ClickHouseRetry.with_retry(fn ->
                 :counters.add(counter, 1, 1)

                 if :counters.get(counter, 1) < 2 do
                   raise %DBConnection.ConnectionError{
                     message: "connection not available",
                     reason: :error,
                     severity: :error
                   }
                 end

                 :ok
               end) == :ok
      end)

      assert :counters.get(counter, 1) == 2
    end

    test "retries on transient ClickHouse table shutdown errors" do
      counter = :counters.new(1, [])

      log =
        capture_log(fn ->
          assert ClickHouseRetry.with_retry(fn ->
                   :counters.add(counter, 1, 1)

                   if :counters.get(counter, 1) < 2 do
                     raise %Ch.Error{
                       code: 242,
                       message: "Table is in readonly mode while shutting down (TABLE_IS_READ_ONLY)"
                     }
                   end

                   :ok
                 end) == :ok
        end)

      assert :counters.get(counter, 1) == 2
      assert log =~ "ClickHouse operation failed"
    end

    test "lets non-transient ClickHouse errors propagate without retry" do
      counter = :counters.new(1, [])

      assert_raise Ch.Error, fn ->
        ClickHouseRetry.with_retry(fn ->
          :counters.add(counter, 1, 1)
          raise %Ch.Error{code: 60, message: "Unknown table"}
        end)
      end

      assert :counters.get(counter, 1) == 1
    end

    test "reraises Mint.TransportError after exhausting retries" do
      counter = :counters.new(1, [])

      capture_log(fn ->
        assert_raise Mint.TransportError, fn ->
          ClickHouseRetry.with_retry(fn ->
            :counters.add(counter, 1, 1)
            raise %Mint.TransportError{reason: :timeout}
          end)
        end
      end)

      assert :counters.get(counter, 1) == 4
    end

    test "lets non-Mint, non-DBConnection exceptions propagate without retry" do
      counter = :counters.new(1, [])

      assert_raise RuntimeError, fn ->
        ClickHouseRetry.with_retry(fn ->
          :counters.add(counter, 1, 1)
          raise "boom"
        end)
      end

      assert :counters.get(counter, 1) == 1
    end
  end
end
