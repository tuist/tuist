defmodule Atlas.LLMs.ErrorsTest do
  use ExUnit.Case, async: true

  alias Atlas.LLMs.Errors

  describe "hard_failure_reason/1" do
    test "classifies provider credit limit failures as permanent" do
      reason = {:api_error, %{status: 402, body: %{"error" => %{"code" => "credit_limit"}}}}

      assert Errors.hard_failure?(reason)
      assert Errors.hard_failure_reason(reason) == :llm_credit_limit
      assert Errors.oban_error(reason) == {:cancel, :llm_credit_limit}
    end

    test "classifies suspended provider accounts as permanent" do
      reason = {:error, "Account is suspended due to a billing issue."}

      assert Errors.hard_failure_reason(reason) == :llm_provider_account_suspended
    end

    test "keeps transient failures retryable" do
      reason = {:error, :overloaded}

      refute Errors.hard_failure?(reason)
      assert Errors.oban_error(reason) == {:error, reason}
    end
  end
end
