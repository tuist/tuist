defmodule Pulse.TestIsolationTest do
  @moduledoc """
  Enforces the test-isolation rules in AGENTS.md by inspecting test sources.

  Tests configure an owned `Pulse.Runtime` instead of node-global state, run
  asynchronously, and use the project case templates that install that runtime.
  The check walks syntax trees rather than matching text, so comments and string
  contents never count. Aliasing another module as `Application` or `System` is
  rejected too, in tests and production modules, so a bare `Application` call
  always means the real one.
  """
  use Pulse.Test.Case, async: true

  @root Path.expand("../..", __DIR__)

  # {module alias segments or erlang module, function} pairs that mutate state
  # shared by every test in the VM.
  @global_mutators %{
    [:Application] => [:put_env, :put_all_env, :delete_env, :stop, :start, :ensure_all_started, :ensure_started],
    [:System] => [:put_env, :delete_env],
    :application => [:set_env, :unset_env, :stop, :start, :ensure_all_started, :ensure_started],
    :os => [:putenv, :unsetenv],
    :persistent_term => [:put, :erase]
  }

  @case_templates [[:Pulse, :Test, :Case], [:PulseWeb, :ConnCase]]
  @reserved_aliases [[:Application], [:System]]

  test "tests never mutate node-global configuration, environment, or the application tree" do
    violations = Enum.flat_map(sources(), &global_mutations/1)
    assert violations == [], format(violations)
  end

  test "test modules are asynchronous and use the owned-runtime case templates" do
    violations =
      sources()
      |> Enum.filter(&String.ends_with?(&1, "_test.exs"))
      |> Enum.flat_map(&case_template_violations/1)

    assert violations == [], format(violations)
  end

  test "production modules never alias another module as Application or System" do
    violations =
      Path.join(@root, "lib/**/*.ex")
      |> Path.wildcard()
      |> Enum.flat_map(fn path ->
        path |> parse() |> collect_global(relative(path)) |> Enum.filter(&String.starts_with?(elem(&1, 2), "aliases"))
      end)

    assert violations == [], format(violations)
  end

  test "the checker recognizes each banned construct" do
    source = """
    defmodule Example do
      use ExUnit.Case, async: false
      alias Pulse.Runtime, as: Application
      def run do
        Application.put_env(:pulse, :key, 1)
        System.put_env("NAME", "value")
        :persistent_term.put(:key, 1)
        Supervisor.terminate_child(Pulse.Supervisor, Pulse.Metrics)
        # Application.put_env(:pulse, :comment, 1) is ignored
        "Application.delete_env(:pulse, :string) is ignored"
      end
    end
    """

    {:ok, ast} = Code.string_to_quoted(source, file: "example_test.exs")
    mutations = ast |> collect_global("example_test.exs") |> Enum.map(&elem(&1, 2))

    assert Enum.sort(mutations) ==
             Enum.sort([
               "aliases a module as Application",
               "calls Application.put_env",
               "calls System.put_env",
               "calls :persistent_term.put",
               "references the application supervisor Pulse.Supervisor"
             ])

    assert ast |> collect_case("example_test.exs") |> Enum.map(&elem(&1, 2)) == [
             "uses ExUnit.Case instead of Pulse.Test.Case or PulseWeb.ConnCase"
           ]
  end

  defp sources do
    Path.wildcard(Path.join(@root, "test/**/*.{ex,exs}"))
  end

  defp parse(path) do
    path |> File.read!() |> Code.string_to_quoted!(file: path)
  end

  defp global_mutations(path), do: path |> parse() |> collect_global(relative(path))
  defp case_template_violations(path), do: path |> parse() |> collect_case(relative(path))

  defp collect_global(ast, file) do
    {_, found} =
      Macro.prewalk(ast, [], fn node, acc ->
        case global_violation(node) do
          nil -> {node, acc}
          message -> {node, [{file, line(node), message} | acc]}
        end
      end)

    Enum.reverse(found)
  end

  defp global_violation({:alias, _, [_module, opts]}) when is_list(opts) do
    case Keyword.get(opts, :as) do
      {:__aliases__, _, parts} when parts in @reserved_aliases -> "aliases a module as #{Enum.join(parts, ".")}"
      _ -> nil
    end
  end

  defp global_violation({{:., _, [{:__aliases__, _, parts}, function]}, _, _}) when is_atom(function) do
    if function in Map.get(@global_mutators, parts, []), do: "calls #{Enum.join(parts, ".")}.#{function}"
  end

  defp global_violation({{:., _, [module, function]}, _, _}) when is_atom(module) and is_atom(function) do
    if function in Map.get(@global_mutators, module, []), do: "calls #{inspect(module)}.#{function}"
  end

  defp global_violation({:__aliases__, _, [:Pulse, :Supervisor]}),
    do: "references the application supervisor Pulse.Supervisor"

  defp global_violation(_node), do: nil

  defp collect_case(ast, file) do
    {_, uses} =
      Macro.prewalk(ast, [], fn
        {:use, meta, [{:__aliases__, _, parts} | rest]} = node, acc -> {node, [{parts, rest, meta} | acc]}
        node, acc -> {node, acc}
      end)

    templates = Enum.filter(uses, fn {parts, _, _} -> parts in @case_templates or parts == [:ExUnit, :Case] end)

    case templates do
      [] ->
        [{file, 1, "does not use Pulse.Test.Case or PulseWeb.ConnCase"}]

      _ ->
        Enum.flat_map(templates, fn {parts, rest, meta} ->
          cond do
            parts == [:ExUnit, :Case] ->
              [{file, meta[:line], "uses ExUnit.Case instead of Pulse.Test.Case or PulseWeb.ConnCase"}]

            async?(rest) ->
              []

            true ->
              [{file, meta[:line], "is not async: true"}]
          end
        end)
    end
  end

  defp async?([opts]) when is_list(opts), do: Keyword.get(opts, :async) == true
  defp async?(_), do: false

  defp line({_, meta, _}) when is_list(meta), do: meta[:line]
  defp line(_), do: nil

  defp relative(path), do: Path.relative_to(path, @root)

  defp format(violations) do
    Enum.map_join(violations, "\n", fn {file, line, message} -> "#{file}:#{line} #{message}" end)
  end
end
