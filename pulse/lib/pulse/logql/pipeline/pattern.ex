defmodule Pulse.LogQL.Pipeline.Pattern do
  @moduledoc """
  LogQL `| pattern` template compilation and matching.

  A template is literal text interleaved with `<name>` capture
  placeholders and `<_>` skip placeholders. Compilation returns a small
  representation the matcher walks in one linear scan of the log line.
  """

  @type token :: {:literal, binary()} | {:capture, String.t()} | :skip
  @type template :: [token()]

  @spec compile(String.t()) :: template()
  def compile(pattern) when is_binary(pattern) do
    ~r/(<[a-zA-Z_][a-zA-Z0-9_]*>)/
    |> Regex.split(pattern, include_captures: true, trim: true)
    |> Enum.map(fn
      "<_>" ->
        :skip

      <<"<", rest::binary>> = part ->
        if Regex.match?(~r/\A[a-zA-Z_][a-zA-Z0-9_]*>\z/, rest),
          do: {:capture, binary_part(rest, 0, byte_size(rest) - 1)},
          else: {:literal, part}

      part ->
        {:literal, part}
    end)
    |> merge_literals([])
  end

  @doc "Compile a parser pattern, rejecting absent, repeated or adjacent named captures."
  @spec compile_parser(String.t()) :: {:ok, template()} | {:error, term()}
  def compile_parser(pattern) do
    parts = compile(pattern)
    names = for {:capture, name} <- parts, do: name

    adjacent? =
      parts
      |> Enum.chunk_every(2, 1, :discard)
      |> Enum.any?(fn [left, right] -> not match?({:literal, _}, left) and not match?({:literal, _}, right) end)

    cond do
      names == [] -> {:error, :missing_capture}
      adjacent? -> {:error, :consecutive_captures}
      length(Enum.uniq(names)) != length(names) -> {:error, :duplicate_capture}
      true -> {:ok, parts}
    end
  end

  @doc """
  Compile a `|>` / `!>` line filter pattern: literals and unnamed `<_>`
  wildcards. Like Loki, a placeholder needs an identifier (`<name>`), other
  `<...>` text is literal, and named or consecutive wildcards are invalid.
  """
  @spec compile_filter(String.t()) :: {:ok, [{:literal, binary()} | :skip]} | {:error, term()}
  def compile_filter(pattern) when is_binary(pattern) do
    parts = compile(pattern)

    cond do
      Enum.any?(parts, &match?({:capture, _}, &1)) -> {:error, :named_capture}
      parts |> Enum.chunk_every(2, 1, :discard) |> Enum.member?([:skip, :skip]) -> {:error, :consecutive_captures}
      true -> {:ok, parts}
    end
  end

  defp merge_literals([], acc), do: Enum.reverse(acc)

  defp merge_literals([{:literal, b} | rest], [{:literal, a} | acc]),
    do: merge_literals(rest, [{:literal, a <> b} | acc])

  defp merge_literals([part | rest], acc), do: merge_literals(rest, [part | acc])

  @doc """
  Whether `line` matches a compiled filter pattern, with Loki's semantics:
  literals occur in order, a wildcard matches at least one byte, and the line
  must end where the pattern does (a trailing wildcard needs remaining text).
  An empty line matches only an empty pattern.
  """
  @spec filter_match?([{:literal, binary()} | :skip], binary()) :: boolean()
  def filter_match?([], line), do: line == ""
  def filter_match?(_parts, ""), do: false

  def filter_match?(parts, line) do
    result =
      parts
      |> Enum.with_index()
      |> Enum.reduce_while(0, fn
        {:skip, _i}, off ->
          {:cont, off}

        {{:literal, lit}, i}, off ->
          case :binary.match(line, lit, scope: {off, byte_size(line) - off}) do
            :nomatch -> {:halt, :nomatch}
            {pos, _len} when i != 0 and pos == off -> {:halt, :nomatch}
            {pos, len} -> {:cont, pos + len}
          end
      end)

    case result do
      :nomatch -> false
      off -> List.last(parts) == :skip == (off != byte_size(line))
    end
  end

  @spec match(template(), String.t()) :: {:ok, %{optional(String.t()) => String.t()}} | :nomatch
  def match(_template, ""), do: {:ok, %{}}

  def match(template, line) when is_binary(line) do
    match_template(template, line, %{})
  end

  defp match_template([], _rest, captures), do: {:ok, captures}

  defp match_template([{:literal, lit} | rest], line, captures) do
    case starts_with?(line, lit) do
      {:ok, remaining} -> match_template(rest, remaining, captures)
      :error -> :nomatch
    end
  end

  defp match_template([{:capture, name}, {:literal, next} | rest], line, captures) do
    case :binary.match(line, next) do
      :nomatch ->
        {:ok, Map.put(captures, name, line)}

      {pos, len} ->
        value = binary_part(line, 0, pos)
        remaining = binary_part(line, pos + len, byte_size(line) - pos - len)
        match_template(rest, remaining, Map.put(captures, name, value))
    end
  end

  defp match_template([{:capture, name}], line, captures) do
    {:ok, Map.put(captures, name, line)}
  end

  defp match_template([:skip, {:literal, next} | rest], line, captures) do
    case :binary.match(line, next) do
      :nomatch ->
        {:ok, captures}

      {pos, len} ->
        remaining = binary_part(line, pos + len, byte_size(line) - pos - len)
        match_template(rest, remaining, captures)
    end
  end

  defp match_template([:skip], _line, captures), do: {:ok, captures}

  defp starts_with?(line, prefix) do
    if byte_size(prefix) <= byte_size(line) and binary_part(line, 0, byte_size(prefix)) == prefix do
      {:ok, binary_part(line, byte_size(prefix), byte_size(line) - byte_size(prefix))}
    else
      :error
    end
  end
end
