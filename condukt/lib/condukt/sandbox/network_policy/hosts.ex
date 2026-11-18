defmodule Condukt.Sandbox.NetworkPolicy.Hosts do
  @moduledoc """
  Host glob matching shared by the `AllowHosts` and `DenyHosts` rules.

  Syntax:

    * `*` matches a single DNS label (no dots).
    * `**` matches one or more dot-separated labels.
    * Literal characters match themselves; comparison is case-insensitive.

  Examples:

      "api.github.com"     # literal
      "*.openai.com"       # one label before the suffix
      "**.googleapis.com"  # one or more labels before the suffix
  """

  @doc """
  Returns whether `host` matches any pattern in the given list.
  """
  def matches_any?(host, patterns) when is_binary(host) and is_list(patterns) do
    Enum.any?(patterns, &matches?(host, &1))
  end

  @doc """
  Single-pattern match. See module docs for the glob syntax.
  """
  def matches?(host, pattern) when is_binary(host) and is_binary(pattern) do
    host = String.downcase(host)
    pattern = String.downcase(pattern)
    regex = compile_pattern(pattern)
    Regex.match?(regex, host)
  end

  defp compile_pattern(pattern) do
    parts =
      pattern
      |> String.graphemes()
      |> tokenize([], [])
      |> Enum.reverse()

    body = Enum.map_join(parts, &token_to_regex/1)

    Regex.compile!("^" <> body <> "$")
  end

  defp tokenize([], current, acc) do
    flush(current, acc)
  end

  defp tokenize(["*", "*" | rest], current, acc) do
    acc = flush(current, acc)
    tokenize(rest, [], [:doublestar | acc])
  end

  defp tokenize(["*" | rest], current, acc) do
    acc = flush(current, acc)
    tokenize(rest, [], [:star | acc])
  end

  defp tokenize([ch | rest], current, acc) do
    tokenize(rest, [ch | current], acc)
  end

  defp flush([], acc), do: acc
  defp flush(current, acc), do: [{:literal, current |> Enum.reverse() |> Enum.join()} | acc]

  defp token_to_regex(:star), do: "[^.]+"
  defp token_to_regex(:doublestar), do: ".+"
  defp token_to_regex({:literal, str}), do: Regex.escape(str)
end
