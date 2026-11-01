defmodule TuistEx.ProjectSetup do
  @moduledoc false

  @compile_alias quote(do: &compile/1)

  @bootstrap """
  # Mix forwards alias arguments only to the last task in a list. Keep the
  # bootstrap in this project module so --no-compile also skips deps.compile,
  # without requiring an SDK module before a cold worker has loaded it.
  defp compile(args) do
    if "--no-compile" not in args do
      compile_tuist_ex()
    end

    Mix.Task.run("deps.loadpaths", ["--no-compile", "--no-deps-check"])
    Mix.Task.run("tuist.compile", args)
  end

  # `deps.compile` rebuilds every dependency it is given, and a rebuilt fetched
  # dependency makes Mix recheck, and possibly recompile, the whole project.
  # Give it only what `deps.loadpaths` would compile: dependencies that are not
  # ok, and local ones.
  defp compile_tuist_ex do
    deps =
      ["tuist_ex"]
      |> Mix.Dep.filter_by_name(Mix.Dep.load_and_cache(), include_children: true)
      |> Enum.reject(&(Mix.Dep.ok?(&1) and &1.scm.fetchable?()))
      |> Enum.map(&Atom.to_string(&1.app))

    if deps != [], do: Mix.Task.run("deps.compile", deps)
  end
  """

  # Earlier releases installed this list alias, and the manual integration guide
  # documented the function for jobs that run with --no-compile. Both compile
  # Tuist's dependencies on every invocation.
  @legacy_compile_alias [
    "deps.compile tuist_ex --include-children",
    "deps.loadpaths --no-compile --no-deps-check",
    "tuist.compile"
  ]

  @legacy_compile_function """
  defp compile(args) do
    if "--no-compile" not in args do
      Mix.Task.run("deps.compile", ["tuist_ex", "--include-children"])
    end

    Mix.Task.run("deps.loadpaths", ["--no-compile", "--no-deps-check"])
    Mix.Task.run("tuist.compile", args)
  end
  """

  def configure(source, config, options \\ []) do
    tuist = Keyword.get(config, :tuist, []) || []
    project = Keyword.get(options, :project, tuist[:project])
    aliases = Keyword.get(config, :aliases, [])
    existing_compile = aliases[:compile]

    with :ok <- validate_project(project),
         {:ok, ast} <- parse(source),
         {:ok, metadata, entries} <- project_entries(ast),
         {:ok, module} <- project_module(ast),
         {:ok, compile_alias, bootstrap_edits} <-
           bootstrap(existing_compile, source, entries, module),
         {:ok, test_alias} <- test_alias(aliases[:test]),
         updates =
           Enum.reject([compile: compile_alias, test: test_alias], fn {key, value} ->
             is_nil(value) or aliases[key] == value
           end),
         {:ok, edits} <- edits(source, metadata, entries, updates, tuist, project) do
      updated =
        (bootstrap_edits ++ edits)
        |> Enum.sort_by(&elem(&1, 0), :desc)
        |> Enum.reduce(source, fn {start, size, replacement}, text ->
          binary_part(text, 0, start) <>
            replacement <>
            binary_part(text, start + size, byte_size(text) - start - size)
        end)

      {:ok, updated |> Code.format_string!() |> IO.iodata_to_binary() |> Kernel.<>("\n")}
    end
  rescue
    error in [SyntaxError, TokenMissingError, ArgumentError] ->
      {:error,
       "Could not update mix.exs safely: #{Exception.message(error)}. No changes were made."}
  end

  defp validate_project(project) when is_binary(project) do
    case String.split(project, "/") do
      [account, name] when account != "" and name != "" -> :ok
      _ -> {:error, "Use --project account/project to select your Tuist project."}
    end
  end

  defp validate_project(_),
    do: {:error, "Use --project account/project to select your Tuist project."}

  defp bootstrap(alias, source, entries, {metadata, expressions}) do
    definitions = Enum.group_by(expressions, &definition_name/1)

    cond do
      alias in [nil, "tuist.compile", @legacy_compile_alias] or
          (is_function(alias, 1) and legacy_bootstrap?(source, entries)) ->
        if Map.has_key?(definitions, {:compile, 1}) or
             Map.has_key?(definitions, {:compile_tuist_ex, 0}) do
          customized_compile_alias()
        else
          {:ok, @compile_alias, [{offset(source, metadata[:end]), 0, "\n" <> @bootstrap}]}
        end

      not is_function(alias, 1) ->
        customized_compile_alias()

      true ->
        case {definitions[{:compile, 1}], definitions[{:compile_tuist_ex, 0}]} do
          {[compile], [helper]} ->
            if same_definitions?([compile, helper], @bootstrap),
              do: {:ok, nil, []},
              else: customized_compile_alias()

          {[compile], nil} ->
            with true <- same_definitions?([compile], @legacy_compile_function),
                 {:ok, start, size} <- definition_span(source, compile) do
              {:ok, nil, [{start, size, String.trim_trailing(@bootstrap)}]}
            else
              _ -> customized_compile_alias()
            end

          _ ->
            customized_compile_alias()
        end
    end
  end

  defp customized_compile_alias do
    {:error,
     "The compile alias is customized. Integrate the Tuist bootstrap alias manually; no changes were made."}
  end

  defp project_module(ast) do
    {_, modules} =
      Macro.prewalk(ast, [], fn
        {:defmodule, metadata, [_, [{_, body}]]} = node, modules ->
          {node, [{metadata, top_level_expressions(body)} | modules]}

        node, modules ->
          {node, modules}
      end)

    modules
    |> Enum.filter(fn {metadata, expressions} ->
      metadata[:end] && Enum.any?(expressions, &(definition_name(&1) == {:project, 0}))
    end)
    |> case do
      [module] ->
        {:ok, module}

      _ ->
        {:error,
         "Expected mix.exs to define project/0 in a module. Configure Tuist manually; no changes were made."}
    end
  end

  defp top_level_expressions({:__block__, _, expressions}) when length(expressions) > 1,
    do: expressions

  defp top_level_expressions(expression), do: [expression]

  defp definition_name({kind, _, [{:when, _, [head | _]} | _]}) when kind in [:def, :defp],
    do: definition_name({kind, [], [head]})

  defp definition_name({kind, _, [{name, _, args} | _]})
       when kind in [:def, :defp] and is_atom(name), do: {name, length(args || [])}

  defp definition_name(_), do: nil

  defp same_definitions?(definitions, expected) do
    {:ok, expected} = parse(expected)
    strip_metadata(definitions) == strip_metadata(top_level_expressions(expected))
  end

  defp strip_metadata(ast) do
    Macro.prewalk(ast, fn
      {name, metadata, args} when is_list(metadata) -> {name, [], args}
      node -> node
    end)
  end

  defp definition_span(source, {_, metadata, _}) do
    if metadata[:end] do
      start = offset(source, metadata)
      {:ok, start, offset(source, metadata[:end]) + byte_size("end") - start}
    else
      :error
    end
  end

  defp test_alias(nil), do: {:ok, "tuist.test"}

  defp test_alias(value) when is_binary(value) do
    case String.split(value, ~r/\s+/, parts: 2) do
      [task | arguments] when task in ["test", "tuist.test"] ->
        {:ok, Enum.join(["tuist.test" | arguments], " ")}

      _ ->
        customized_test_alias()
    end
  end

  defp test_alias(values) when is_list(values) do
    tasks =
      Enum.filter(
        values,
        &(is_binary(&1) and hd(String.split(&1) ++ [""]) in ["test", "tuist.test"])
      )

    if length(tasks) == 1 and Enum.all?(values, &is_binary/1) do
      {:ok, replacement} = test_alias(hd(tasks))
      {:ok, Enum.map(values, fn value -> if value == hd(tasks), do: replacement, else: value end)}
    else
      customized_test_alias()
    end
  end

  defp test_alias(_), do: customized_test_alias()

  defp customized_test_alias do
    {:error,
     "The test alias is customized. Integrate tuist.test manually, preserving your test setup; no changes were made."}
  end

  defp legacy_bootstrap?(source, entries) do
    with {_, {:__block__, _, [aliases]}} <-
           Enum.find(entries, fn {key, _} -> key_name(key) == :aliases end),
         true <- is_list(aliases),
         {_, value} <- Enum.find(aliases, fn {key, _} -> key_name(key) == :compile end),
         {:ok, start, size} <- span(source, value) do
      Regex.match?(
        ~r/\A&Code\.eval_string\(File\.read!\("[^"\n]*tuist_ex\/compile\.exs"\),\s*args:\s*&1\)\z/,
        binary_part(source, start, size)
      )
    else
      _ -> false
    end
  end

  defp parse(source) do
    Code.string_to_quoted(source,
      columns: true,
      token_metadata: true,
      literal_encoder: fn value, metadata -> {:ok, {:__block__, metadata, [value]}} end
    )
    |> case do
      {:ok, ast} -> {:ok, ast}
      {:error, _} -> {:error, "Could not parse mix.exs. No changes were made."}
    end
  end

  defp project_entries(ast) do
    {_, projects} =
      Macro.prewalk(ast, [], fn
        {:def, _, [{:project, _, args}, body]} = node, projects when args in [nil, []] ->
          value = Enum.find_value(body, fn {key, value} -> if key_name(key) == :do, do: value end)
          {node, [last_expression(value) | projects]}

        node, projects ->
          {node, projects}
      end)

    case projects do
      [{:__block__, metadata, [entries]}] when is_list(entries) ->
        if Enum.all?(entries, &match?({{:__block__, _, [_]}, _}, &1)) do
          {:ok, metadata, entries}
        else
          unsupported_project()
        end

      _ ->
        unsupported_project()
    end
  end

  defp last_expression({:__block__, _, expressions} = node) do
    if length(expressions) > 1, do: List.last(expressions), else: node
  end

  defp last_expression(node), do: node

  defp unsupported_project do
    {:error,
     "Expected project/0 to return a keyword list. Configure Tuist manually; no changes were made."}
  end

  defp key_name({:__block__, _, [key]}), do: key
  defp key_name(_), do: nil

  defp edits(source, metadata, entries, updates, tuist, project) do
    settings = [
      project: project,
      cache: if(is_list(tuist[:cache]), do: tuist[:cache], else: true)
    ]

    fields = [
      {:aliases, updates != [],
       fn value -> "Keyword.merge(#{value}, #{Macro.to_string(updates)})" end,
       Macro.to_string(updates)},
      {:tuist, tuist[:project] != project or tuist[:cache] in [nil, false],
       fn value -> "Keyword.merge(#{value}, #{inspect(settings)})" end, inspect(settings)}
    ]

    Enum.reduce_while(fields, {:ok, [], []}, fn {key, changed?, wrap, initial},
                                                {:ok, edits, additions} ->
      entry = Enum.find(entries, fn {name, _} -> key_name(name) == key end)

      cond do
        not changed? ->
          {:cont, {:ok, edits, additions}}

        is_nil(entry) ->
          {:cont, {:ok, edits, ["#{key}: #{initial}" | additions]}}

        true ->
          {_, value} = entry

          result =
            if key == :aliases do
              alias_edits(source, value, wrap, updates)
            else
              wrapped_edit(source, value, wrap)
            end

          case result do
            {:ok, new_edits} -> {:cont, {:ok, new_edits ++ edits, additions}}
            :error -> {:halt, {:error, "Could not locate #{key} safely. No changes were made."}}
          end
      end
    end)
    |> case do
      {:ok, edits, []} ->
        {:ok, edits}

      {:ok, edits, additions} ->
        start = offset(source, metadata) + 1
        {:ok, [{start, 0, Enum.join(Enum.reverse(additions), ",\n") <> ",\n"} | edits]}

      error ->
        error
    end
  end

  defp alias_edits(source, {:__block__, metadata, [entries]}, _wrap, updates)
       when is_list(entries) do
    Enum.reduce_while(updates, {:ok, [], []}, fn {name, replacement}, {:ok, edits, additions} ->
      case Enum.find(entries, fn {key, _} -> key_name(key) == name end) do
        {_, value} ->
          case span(source, value) do
            {:ok, start, size} ->
              {:cont, {:ok, [{start, size, Macro.to_string(replacement)} | edits], additions}}

            :error ->
              {:halt, :error}
          end

        nil ->
          {:cont, {:ok, edits, ["#{name}: #{Macro.to_string(replacement)}" | additions]}}
      end
    end)
    |> case do
      {:ok, edits, []} ->
        {:ok, edits}

      {:ok, edits, additions} ->
        {:ok,
         [
           {offset(source, metadata) + 1, 0, Enum.join(Enum.reverse(additions), ", ") <> ", "}
           | edits
         ]}

      error ->
        error
    end
  end

  defp alias_edits(source, value, _wrap, updates) do
    wrapped_edit(source, value, fn original ->
      compile_updates = Keyword.take(updates, [:compile])

      base =
        if compile_updates == [],
          do: original,
          else: "Keyword.merge(#{original}, #{Macro.to_string(compile_updates)})"

      if Keyword.has_key?(updates, :test) do
        # Keep environment-dependent preparation in the original expression.
        """
        Keyword.update(#{base}, :test, "tuist.test", fn tasks ->
          tasks |> List.wrap() |> Enum.map(fn
            task when is_binary(task) -> String.replace(task, ~r/\\Atest(?=\\s|\\z)/, "tuist.test")
            task -> task
          end)
        end)
        """
        |> String.trim()
      else
        base
      end
    end)
  end

  defp wrapped_edit(source, value, wrap) do
    with {:ok, start, size} <- span(source, value) do
      {:ok, [{start, size, wrap.(binary_part(source, start, size))}]}
    end
  end

  defp span(source, {:__block__, metadata, [value]}) when is_binary(value) do
    start = offset(source, metadata)
    literal = inspect(value)

    if binary_part(source, start, byte_size(literal)) == literal,
      do: {:ok, start, byte_size(literal)},
      else: :error
  end

  defp span(source, {name, metadata, _} = ast) do
    {_, closings} =
      Macro.prewalk(ast, [], fn
        {_, meta, _} = node, positions when is_list(meta) ->
          {node, if(meta[:closing], do: [meta[:closing] | positions], else: positions)}

        node, positions ->
          {node, positions}
      end)

    closing =
      metadata[:closing] ||
        if(name == :& and closings != [], do: Enum.max_by(closings, &{&1[:line], &1[:column]}))

    if (name == :__block__ or name == :& or not is_atom(name) or not Macro.operator?(name, 2)) and
         closing do
      {_, positions} =
        Macro.prewalk(ast, [], fn
          {_, meta, _} = node, positions when is_list(meta) ->
            positions = if meta[:line] && meta[:column], do: [meta | positions], else: positions
            {node, positions}

          node, positions ->
            {node, positions}
        end)

      first = Enum.min_by(positions, &{&1[:line], &1[:column]})
      start = offset(source, first)
      {:ok, start, offset(source, closing) + 1 - start}
    else
      :error
    end
  end

  defp span(_, _), do: :error

  defp offset(source, metadata) do
    {before, [line | _]} = source |> String.split("\n") |> Enum.split(metadata[:line] - 1)

    Enum.reduce(before, 0, &(byte_size(&1) + 1 + &2)) +
      byte_size(String.slice(line, 0, metadata[:column] - 1))
  end
end
