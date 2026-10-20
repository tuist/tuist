defmodule TuistEx.Analytics.IsolatedTest do
  use ExUnit.Case, async: true

  alias TuistEx.Analytics.Isolated

  test "returns what the function returns" do
    assert Isolated.run(fn -> {:ok, 1} end, 1_000) == {:ok, 1}
  end

  @tag :capture_log
  test "turns an exception into an error instead of raising in the caller" do
    assert {:error, {%RuntimeError{message: "boom"}, _stacktrace}} =
             Isolated.run(fn -> raise "boom" end, 1_000)
  end

  test "gives up on work that takes too long" do
    assert Isolated.run(fn -> Process.sleep(:infinity) end, 50) == {:error, :timeout}
  end
end
