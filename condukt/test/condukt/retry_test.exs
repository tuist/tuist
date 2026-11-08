defmodule Condukt.RetryTest do
  use ExUnit.Case, async: true

  alias Condukt.Retry

  describe "normalize/1" do
    test "nil and true return the default policy" do
      assert Retry.normalize(nil) == Retry.default()
      assert Retry.normalize(true) == Retry.default()
    end

    test "false returns the disabled policy" do
      assert Retry.normalize(false) == Retry.disabled()
      assert Retry.disabled().max_attempts == 1
    end

    test "a struct is returned as-is" do
      policy = %Retry{max_attempts: 7}
      assert Retry.normalize(policy) == policy
    end

    test "a keyword list overrides fields" do
      policy = Retry.normalize(max_attempts: 5, base_delay_ms: 10)
      assert policy.max_attempts == 5
      assert policy.base_delay_ms == 10
      assert policy.max_delay_ms == Retry.default().max_delay_ms
    end
  end

  describe "default_classify/1" do
    test "retries transient HTTP statuses on API.Request" do
      for status <- [408, 425, 429, 500, 502, 503, 504] do
        assert Retry.default_classify(%ReqLLM.Error.API.Request{status: status, reason: "x"}) == :retry
      end
    end

    test "stops on non-transient HTTP statuses" do
      for status <- [400, 401, 403, 404, 422] do
        assert Retry.default_classify(%ReqLLM.Error.API.Request{status: status, reason: "x"}) == :stop
      end
    end

    test "retries transient statuses wrapped in API.Stream" do
      cause = %ReqLLM.Error.API.Request{status: 503, reason: "overloaded"}
      assert Retry.default_classify(%ReqLLM.Error.API.Stream{reason: "Stream failed: ...", cause: cause}) == :retry
    end

    test "retries Stream errors with overload/rate-limit/timeout text when no cause is present" do
      for reason <- [
            "Stream failed: service overloaded, please try again later",
            "Stream failed: rate limit exceeded",
            "Stream failed: connection timed out"
          ] do
        assert Retry.default_classify(%ReqLLM.Error.API.Stream{reason: reason, cause: nil}) == :retry
      end
    end

    test "stops on Stream errors with non-transient text" do
      assert Retry.default_classify(%ReqLLM.Error.API.Stream{reason: "Stream failed: malformed response", cause: nil}) ==
               :stop
    end

    test "stops on unknown error shapes" do
      assert Retry.default_classify(:something_else) == :stop
      assert Retry.default_classify(%RuntimeError{message: "boom"}) == :stop
    end
  end

  describe "with_retry/3" do
    test "returns the successful result without retrying" do
      attempts = :counters.new(1, [:atomics])

      result =
        Retry.with_retry(Retry.normalize(max_attempts: 3, base_delay_ms: 1), fn -> false end, fn ->
          :counters.add(attempts, 1, 1)
          {:ok, :done}
        end)

      assert result == {:ok, :done}
      assert :counters.get(attempts, 1) == 1
    end

    test "retries transient errors up to max_attempts" do
      attempts = :counters.new(1, [:atomics])

      result =
        Retry.with_retry(Retry.normalize(max_attempts: 3, base_delay_ms: 1, max_delay_ms: 2), fn -> false end, fn ->
          :counters.add(attempts, 1, 1)
          {:error, %ReqLLM.Error.API.Request{status: 503, reason: "overloaded"}}
        end)

      assert {:error, %ReqLLM.Error.API.Request{status: 503}} = result
      assert :counters.get(attempts, 1) == 3
    end

    test "succeeds after a transient failure" do
      attempts = :counters.new(1, [:atomics])

      result =
        Retry.with_retry(Retry.normalize(max_attempts: 3, base_delay_ms: 1, max_delay_ms: 2), fn -> false end, fn ->
          case :counters.add(attempts, 1, 1) do
            _ ->
              if :counters.get(attempts, 1) < 2 do
                {:error, %ReqLLM.Error.API.Request{status: 503, reason: "overloaded"}}
              else
                {:ok, :recovered}
              end
          end
        end)

      assert result == {:ok, :recovered}
      assert :counters.get(attempts, 1) == 2
    end

    test "does not retry non-transient errors" do
      attempts = :counters.new(1, [:atomics])

      result =
        Retry.with_retry(Retry.normalize(max_attempts: 3, base_delay_ms: 1, max_delay_ms: 2), fn -> false end, fn ->
          :counters.add(attempts, 1, 1)
          {:error, %ReqLLM.Error.API.Request{status: 400, reason: "bad request"}}
        end)

      assert {:error, %ReqLLM.Error.API.Request{status: 400}} = result
      assert :counters.get(attempts, 1) == 1
    end

    test "stops retrying once emitted? returns true" do
      attempts = :counters.new(1, [:atomics])
      emitted = :counters.new(1, [:atomics])

      emitted? = fn -> :counters.get(emitted, 1) > 0 end

      result =
        Retry.with_retry(Retry.normalize(max_attempts: 5, base_delay_ms: 1, max_delay_ms: 2), emitted?, fn ->
          :counters.add(attempts, 1, 1)
          :counters.add(emitted, 1, 1)
          {:error, %ReqLLM.Error.API.Request{status: 503, reason: "overloaded"}}
        end)

      assert {:error, %ReqLLM.Error.API.Request{status: 503}} = result
      assert :counters.get(attempts, 1) == 1
    end

    test "disabled policy runs exactly once" do
      attempts = :counters.new(1, [:atomics])

      result =
        Retry.with_retry(Retry.disabled(), fn -> false end, fn ->
          :counters.add(attempts, 1, 1)
          {:error, %ReqLLM.Error.API.Request{status: 503, reason: "overloaded"}}
        end)

      assert {:error, %ReqLLM.Error.API.Request{status: 503}} = result
      assert :counters.get(attempts, 1) == 1
    end

    test "an interrupted backoff returns its error without another attempt" do
      attempts = :counters.new(1, [:atomics])
      test_pid = self()

      task =
        Task.async(fn ->
          Retry.with_retry(
            Retry.default(),
            fn -> false end,
            fn ->
              :counters.add(attempts, 1, 1)
              {:error, %ReqLLM.Error.API.Request{status: 503, reason: "overloaded"}}
            end,
            fn _delay ->
              send(test_pid, {:waiting, self()})
              receive do: (:cancel -> {:error, :aborted})
            end
          )
        end)

      assert_receive {:waiting, worker}
      send(worker, :cancel)
      assert Task.await(task) == {:error, :aborted}
      assert :counters.get(attempts, 1) == 1
    end

    test "custom classify overrides default behavior" do
      attempts = :counters.new(1, [:atomics])

      policy =
        Retry.normalize(
          max_attempts: 3,
          base_delay_ms: 1,
          max_delay_ms: 2,
          classify: fn
            :please_retry -> :retry
            _ -> :stop
          end
        )

      result =
        Retry.with_retry(policy, fn -> false end, fn ->
          :counters.add(attempts, 1, 1)
          {:error, :please_retry}
        end)

      assert result == {:error, :please_retry}
      assert :counters.get(attempts, 1) == 3
    end
  end
end
