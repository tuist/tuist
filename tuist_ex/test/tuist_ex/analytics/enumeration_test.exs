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

    assert Enumeration.tests_of(modules, {[], []}) == [
             %{module: "CartTest", suite: "", name: "adds", enabled: true},
             %{module: "CartTest", suite: "checkout/1", name: "charges", enabled: true}
           ]

    # A test the configuration excludes, or one tagged to be skipped, is
    # listed disabled.
    tagged = fn name, tags ->
      %ExUnit.Test{name: name, module: CartTest, tags: Map.merge(%{describe: nil}, tags)}
    end

    assert [%{name: "calls the gateway", enabled: false}, %{name: "pending", enabled: false}] =
             Enumeration.tests_of(
               [
                 %ExUnit.TestModule{
                   name: CartTest,
                   tests: [
                     tagged.(:"test calls the gateway", %{integration: true}),
                     tagged.(:"test pending", %{skip: true})
                   ]
                 }
               ],
               {[], [:integration]}
             )
  end

  test "keeps the formatter's list as it is when every test was reported" do
    reported = [%{module: "CartTest", suite: "", name: "adds", enabled: true}]
    assert Enumeration.complete(%{tests: reported ++ reported}, false) == reported
  end

  test "puts standard error and the compiler options back when the files cannot be loaded",
       %{tmp_dir: dir} do
    broken = Path.join(dir, "broken_test.exs")
    File.write!(broken, "defmodule Broken do")
    slow = Path.join(dir, "slow_test.exs")
    File.write!(slow, "Process.sleep(5_000)")

    standard_error = Process.whereis(:standard_error)
    # Only the ones it sets: other tests change the rest as they run.
    touched = [:docs, :debug_info, :infer_signatures]
    compiler_options = Map.take(Code.compiler_options(), touched)

    for {file, timeout, reason} <- [{broken, 60_000, :compile}, {slow, 100, :timeout}] do
      enumeration = %{
        tests: [],
        project: %{files: [file], elixirc_options: []},
        filters: {[], []}
      }

      assert {:error, error} = Enumeration.complete(enumeration, true, timeout)
      assert error == reason or match?({^reason, _}, error)
      assert Process.whereis(:standard_error) == standard_error
      assert Map.take(Code.compiler_options(), touched) == compiler_options
    end
  end

  test "tells the filters the run's arguments add from the project's own" do
    assert Enumeration.cli_filters(["--cover"]) == {[], []}

    assert {[:focus, {:test, %Regex{}}, :slow], [:wip, :test]} =
             Enumeration.cli_filters(
               ~w(--only focus --name-pattern=cart --include slow --exclude wip --seed 0)
             )

    assert Enumeration.cli_filters(["test/cart_test.exs:12"]) ==
             {[location: {"test/cart_test.exs", 12}], [:test]}

    # What the run used, as `mix test` merged the project's exclusions in.
    assert Enumeration.config_filters([:focus], [:test, :integration], {[:focus], [:test]}) ==
             {[], [:integration]}
  end
end
