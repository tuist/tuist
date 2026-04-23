defmodule Credo.Checks.DisallowParensInPlugTest do
  use Credo.Test.Case

  alias Credo.Checks.DisallowParensInPlug

  describe "when plug declarations use parentheses" do
    test "it reports a violation for single-line calls" do
      """
      defmodule Example do
        use Phoenix.Controller

        plug(MyPlug)
      end
      """
      |> to_source_file()
      |> run_check(DisallowParensInPlug)
      |> assert_issue()
    end

    test "it reports a violation for multiline calls" do
      """
      defmodule Example do
        use Phoenix.Controller

        plug(
          MyPlug,
          :show when action in [:show]
        )
      end
      """
      |> to_source_file()
      |> run_check(DisallowParensInPlug)
      |> assert_issue()
    end
  end

  describe "when plug declarations omit parentheses" do
    test "it reports no violations" do
      """
      defmodule Example do
        use Phoenix.Controller

        plug MyPlug
        plug MyPlug, :show when action in [:show]
      end
      """
      |> to_source_file()
      |> run_check(DisallowParensInPlug)
      |> refute_issues()
    end
  end
end
