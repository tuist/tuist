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

  describe "with_result_retry/2" do
    test "retries a tagged per-user memory error" do
      counter = :counters.new(1, [])

      log =
        capture_log(fn ->
          assert {:ok, :result} =
                   ClickHouseRetry.with_result_retry(
                     fn ->
                       :counters.add(counter, 1, 1)

                       if :counters.get(counter, 1) == 1 do
                         {:error, %Ch.Error{code: 241, message: "Memory limit (for user) exceeded"}}
                       else
                         {:ok, :result}
                       end
                     end,
                     user_memory_retries: 1
                   )
        end)

      assert :counters.get(counter, 1) == 2
      assert log =~ "ClickHouse user memory budget is busy"
    end

    test "returns the tagged error when the retry budget is exhausted" do
      error = %Ch.Error{code: 241, message: "Memory limit (for user) exceeded"}

      assert {:error, ^error} =
               ClickHouseRetry.with_result_retry(fn -> {:error, error} end,
                 user_memory_retries: 0
               )
    end

    test "does not retry unrelated ClickHouse errors" do
      counter = :counters.new(1, [])
      error = %Ch.Error{code: 62, message: "Syntax error"}

      assert {:error, ^error} =
               ClickHouseRetry.with_result_retry(
                 fn ->
                   :counters.add(counter, 1, 1)
                   {:error, error}
                 end,
                 user_memory_retries: 1
               )

      assert :counters.get(counter, 1) == 1
    end

    test "retries a tagged transport error" do
      counter = :counters.new(1, [])

      capture_log(fn ->
        assert {:ok, :result} =
                 ClickHouseRetry.with_result_retry(
                   fn ->
                     :counters.add(counter, 1, 1)

                     if :counters.get(counter, 1) == 1 do
                       {:error, %Mint.TransportError{reason: :closed}}
                     else
                       {:ok, :result}
                     end
                   end,
                   transport_retries: 1,
                   user_memory_retries: 0
                 )
      end)

      assert :counters.get(counter, 1) == 2
    end

    test "returns an unrelated tagged error unchanged" do
      assert {:error, :unexpected} =
               ClickHouseRetry.with_result_retry(fn -> {:error, :unexpected} end)
    end
  end
end
