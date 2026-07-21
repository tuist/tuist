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

  describe "with_retry_result/1" do
    test "returns the result on success without retrying" do
      counter = :counters.new(1, [])

      result =
        ClickHouseRetry.with_retry_result(fn ->
          :counters.add(counter, 1, 1)
          {:ok, :result}
        end)

      assert result == {:ok, :result}
      assert :counters.get(counter, 1) == 1
    end

    test "retries a returned transport error and succeeds" do
      counter = :counters.new(1, [])

      log =
        capture_log(fn ->
          assert ClickHouseRetry.with_retry_result(fn ->
                   :counters.add(counter, 1, 1)

                   if :counters.get(counter, 1) < 2 do
                     {:error, %Mint.TransportError{reason: :closed}}
                   else
                     {:ok, :result}
                   end
                 end) == {:ok, :result}
        end)

      assert :counters.get(counter, 1) == 2
      assert log =~ "retrying in"
    end

    test "gives up after exhausting retries and returns the error" do
      counter = :counters.new(1, [])

      capture_log(fn ->
        assert {:error, %Mint.TransportError{}} =
                 ClickHouseRetry.with_retry_result(fn ->
                   :counters.add(counter, 1, 1)
                   {:error, %Mint.TransportError{reason: :closed}}
                 end)
      end)

      assert :counters.get(counter, 1) == 4
    end

    test "does not retry a ClickHouse query error" do
      counter = :counters.new(1, [])

      assert {:error, %Ch.Error{code: 241}} =
               ClickHouseRetry.with_retry_result(fn ->
                 :counters.add(counter, 1, 1)
                 {:error, %Ch.Error{code: 241, message: "memory limit exceeded"}}
               end)

      assert :counters.get(counter, 1) == 1
    end
  end
end
