defmodule TuistEx.ProjectSetup do
  @moduledoc false

  @compile_alias [
    "deps.compile tuist_ex --include-children",
    "deps.loadpaths --no-compile --no-deps-check",
    "tuist.compile"
  ]

  def configure(source, config, options \\ []) do
    tuist = Keyword.get(config, :tuist, []) || []
    project = Keyword.get(options, :project, tuist[:project])
    aliases = Keyword.get(config, :aliases, [])
    existing_compile = aliases[:compile]

    with :ok <- validate_project(project),
         {:ok, ast} <- parse(source),
         {:ok, metadata, entries} <- project_entries(ast),
         :ok <- validate_alias(existing_compile, source, entries),
         {:ok, test_alias} <- test_alias(aliases[:test]),
         updates =
           Enum.reject([compile: @compile_alias, test: test_alias], fn {key, value} ->
             aliases[key] == value
           end),
         {:ok, edits} <-
           edits(source, metadata, entries, updates, tuist, project, coverage_tool?(config)) do
      updated =
        edits
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

  # Mix runs an umbrella's tests in each of its applications, with their own
  # `test_coverage`, so its root has nothing to set.
  defp coverage_tool?(config) do
    is_nil(config[:apps_path]) and
      case Keyword.get(config, :test_coverage) do
        nil -> true
        options when is_list(options) -> is_nil(options[:tool])
        _ -> false
      end
  end

  defp validate_project(project) when is_binary(project) do
    case String.split(project, "/") do
      [account, name] when account != "" and name != "" -> :ok
      _ -> {:error, "Use --project account/project to select your Tuist project."}
    end
  end

  defp validate_project(_),
    do: {:error, "Use --project account/project to select your Tuist project."}

  defp validate_alias(alias, source, entries) do
    if alias in [nil, "tuist.compile", @compile_alias] or
         (is_function(alias, 1) and legacy_bootstrap?(source, entries)) do
      :ok
    else
      {:error,
       "The compile alias is customized. Integrate the Tuist bootstrap alias manually; no changes were made."}
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

  defp edits(source, metadata, entries, updates, tuist, project, coverage_tool?) do
    settings = [
      project: project,
      cache: if(is_list(tuist[:cache]), do: tuist[:cache], else: true)
    ]

    fields = [
      {:aliases, updates != [], fn value -> "Keyword.merge(#{value}, #{inspect(updates)})" end,
       inspect(updates)},
      {:tuist, tuist[:project] != project or tuist[:cache] in [nil, false],
       fn value -> "Keyword.merge(#{value}, #{inspect(settings)})" end, inspect(settings)},
      {:test_coverage, coverage_tool?,
       fn value -> "Keyword.put_new(#{value}, :tool, TuistEx.Coverage)" end,
       "[tool: TuistEx.Coverage]"}
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
            case key do
              :aliases -> alias_edits(source, value, wrap, updates)
              :test_coverage -> keyword_edit(source, value, wrap, "tool: TuistEx.Coverage")
              _ -> wrapped_edit(source, value, wrap)
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
              {:cont, {:ok, [{start, size, inspect(replacement)} | edits], additions}}

            :error ->
              {:halt, :error}
          end

        nil ->
          {:cont, {:ok, edits, ["#{name}: #{inspect(replacement)}" | additions]}}
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
          else: "Keyword.merge(#{original}, #{inspect(compile_updates)})"

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

  # A literal keyword list takes the entry first; anything else is wrapped.
  defp keyword_edit(source, {:__block__, metadata, [entries]}, _wrap, entry)
       when is_list(entries) do
    separator = if entries == [], do: "", else: ", "
    {:ok, [{offset(source, metadata) + 1, 0, entry <> separator}]}
  end

  defp keyword_edit(source, value, wrap, _entry), do: wrapped_edit(source, value, wrap)

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
