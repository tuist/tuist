defmodule Mix.Tasks.Tuist.TestTest do
  use ExUnit.Case, async: false

  alias Mix.Tasks.Tuist.Test, as: Task

  setup do
    formatters = Application.get_env(:ex_unit, :formatters)
    analytics_options = Application.get_env(:tuist_ex, :analytics_options)

    on_exit(fn ->
      if formatters do
        Application.put_env(:ex_unit, :formatters, formatters)
      else
        Application.delete_env(:ex_unit, :formatters)
      end

      if analytics_options do
        Application.put_env(:tuist_ex, :analytics_options, analytics_options)
      else
        Application.delete_env(:tuist_ex, :analytics_options)
      end
    end)
  end

  test "takes the same command line as mix test, keeping only its own options" do
    assert {[url: "https://tuist.example", retries: 2],
            ["test/a_test.exs:12", "--trace", "--only", "slow"]} =
             Task.split_args([
               "test/a_test.exs:12",
               "--url",
               "https://tuist.example",
               "--trace",
               "--retries=2",
               "--only",
               "slow"
             ])
  end

  test "still accepts the `--` separator older versions required" do
    assert {[url: "https://tuist.example"], ["--trace"]} =
             Task.split_args(["--url", "https://tuist.example", "--", "--trace"])
  end

  test "parses --project when no forwarded args are given" do
    assert {[project: "acme/widgets"], []} = Task.split_args(["--project", "acme/widgets"])
  end

  test "rejects an own option without a usable value" do
    assert_raise Mix.Error, ~r/--retries expects a number/, fn ->
      Task.split_args(["--retries", "many"])
    end

    assert_raise Mix.Error, ~r/--project expects a value/, fn ->
      Task.split_args(["--project"])
    end
  end

  test "retries are off unless asked for, by flag first and then the environment" do
    assert Task.retries([], fn _ -> nil end) == 0
    assert Task.retries([retries: 2], fn _ -> "5" end) == 2
    assert Task.retries([], fn "TUIST_TEST_RETRIES" -> "3" end) == 3
    assert Task.retries([], fn "TUIST_TEST_RETRIES" -> "nope" end) == 0
  end

  test "configure/1 appends the analytics formatter without dropping existing ones" do
    Application.put_env(:ex_unit, :formatters, [ExUnit.CLIFormatter])
    :ok = Task.configure(project: "acme/widgets")

    formatters = Application.get_env(:ex_unit, :formatters)
    assert ExUnit.CLIFormatter in formatters
    assert TuistEx.Analytics.ExUnitFormatter in formatters
    assert Application.get_env(:tuist_ex, :analytics_options) == [project: "acme/widgets"]
  end

  test "configure/1 does not duplicate the analytics formatter" do
    Application.put_env(:ex_unit, :formatters, [
      ExUnit.CLIFormatter,
      TuistEx.Analytics.ExUnitFormatter
    ])

    :ok = Task.configure([])

    formatters = Application.get_env(:ex_unit, :formatters)
    assert Enum.count(formatters, &(&1 == TuistEx.Analytics.ExUnitFormatter)) == 1
  end

  test "declares :test as the preferred CLI env" do
    # The attribute prevents `mix tuist.test` from picking up whatever env
    # the invoker happened to be in (usually :dev), which otherwise breaks
    # `mix test` before any tests run.
    attrs = Task.__info__(:attributes)
    assert Keyword.get(attrs, :preferred_cli_env) == [:test]
  end
end
