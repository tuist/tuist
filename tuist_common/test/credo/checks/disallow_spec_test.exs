defmodule Credo.Checks.DisallowSpecTest do
  use Credo.Test.Case

  alias Credo.Checks.DisallowSpec

  describe "when @spec is used" do
    test "it reports a violation" do
      """
      defmodule Example do
        @spec foo() :: :ok
        def foo, do: :ok
      end
      """
      |> to_source_file()
      |> run_check(DisallowSpec)
      |> assert_issue()
    end
  end

  describe "when @spec is not used" do
    test "it reports no violations" do
      """
      defmodule Example do
        def foo, do: :ok
      end
      """
      |> to_source_file()
      |> run_check(DisallowSpec)
      |> refute_issues()
    end
  end
end
