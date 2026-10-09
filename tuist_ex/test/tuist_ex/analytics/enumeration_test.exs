defmodule TuistEx.Analytics.EnumerationTest do
  use ExUnit.Case, async: true

  alias TuistEx.Analytics.Enumeration

  @moduletag :tmp_dir

  test "loads the suite only when the run's arguments keep tests from being reported" do
    for args <- [[], ["--only", "focus"], ["--exclude=slow"], ["--name-pattern", "cart"]],
        do: refute(Enumeration.load?(args), inspect(args))

    for args <- [
          ["--stale"],
          ["--failed"],
          ["--max-failures", "1"],
          ["--max-failures=1"],
          ["test/cart_test.exs"],
          ["test/cart_test.exs:12"],
          ["--seed", "0", "test/cart_test.exs"]
        ],
        do: assert(Enumeration.load?(args), inspect(args))
  end

  test "finds the test files mix test loads", %{tmp_dir: dir} do
    for file <- ~w(test/cart_test.exs test/nested/order_test.exs test/test_helper.exs
                   test/support/case.ex test/misnamed.exs other/extra_test.exs) do
      path = Path.join(dir, file)
      File.mkdir_p!(Path.dirname(path))
      File.write!(path, "")
    end

    expand = fn files -> Enum.map(files, &Path.join(dir, &1)) end

    assert Enumeration.project([], dir).files ==
             expand.(~w(test/cart_test.exs test/nested/order_test.exs))

    # The filters see paths relative to the project, as `mix test`'s do.
    config = [
      test_paths: ["test", "other"],
      test_load_filters: [~r/^test\/nested\//, "other/extra_test.exs"],
      test_elixirc_options: [docs: true]
    ]

    assert Enumeration.project(config, dir) == %{
             files: expand.(~w(test/nested/order_test.exs other/extra_test.exs)),
             elixirc_options: [docs: true]
           }
  end

  test "names each test of a module as the formatter does, once" do
    test = fn name, describe ->
      %ExUnit.Test{
        name: name,
        module: CartTest,
        tags: %{describe: describe, test_type: :test}
      }
    end

    modules = [
      %ExUnit.TestModule{
        name: CartTest,
        tests: [test.(:"test adds", nil), test.(:"test checkout/1 charges", "checkout/1")]
      },
      # A parameterized module defines its tests once and runs them per
      # parameter.
      %ExUnit.TestModule{name: CartTest, tests: [test.(:"test adds", nil)]}
    ]

    assert Enumeration.tests_of(modules) == [
             %{module: "CartTest", suite: "", name: "adds"},
             %{module: "CartTest", suite: "checkout/1", name: "charges"}
           ]
  end

  test "keeps the formatter's list as it is when every test was reported" do
    reported = [%{module: "CartTest", suite: "", name: "adds"}]

    assert Enumeration.complete(reported ++ reported, %{files: [], elixirc_options: []}, false) ==
             reported
  end
end
