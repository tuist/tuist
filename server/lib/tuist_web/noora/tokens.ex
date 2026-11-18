defmodule TuistWeb.Noora.Tokens do
  @moduledoc """
  Reads Noora's design tokens from `noora/css/tokens.css` at compile time.

  The stylesheet is the single source of truth. Tokens are grouped by the
  section comments that precede them (`/* Spacing */`, `/* Radius */`, …), so
  the foundations pages pick the sections they document by name. Only the
  top-level `:root` declarations are read; theme overrides nested in
  `&[data-theme="dark"]` blocks are skipped, since the pages render tokens
  through `var(...)` and the browser resolves the active theme.
  """

  @path Mix.Project.deps_paths() |> Map.fetch!(:noora) |> Path.join("css/tokens.css")
  @external_resource @path

  @tokens (fn ->
             count = fn string, character -> length(String.split(string, character)) - 1 end

             @path
             |> File.read!()
             |> String.split("\n")
             |> Enum.reduce({nil, 0, nil, []}, fn line, {section, depth, pending, tokens} ->
               trimmed = String.trim(line)
               depth_before = depth
               depth = depth + count.(trimmed, "{") - count.(trimmed, "}")

               cond do
                 pending != nil ->
                   value = pending.value <> " " <> trimmed

                   if String.ends_with?(trimmed, ";") do
                     {section, depth, nil, [%{pending | value: String.trim_trailing(value, ";")} | tokens]}
                   else
                     {section, depth, %{pending | value: value}, tokens}
                   end

                 depth_before != 1 ->
                   {section, depth, nil, tokens}

                 match = Regex.run(~r|^/\*\s*(.+?)\s*\*/$|, trimmed) ->
                   {Enum.at(match, 1), depth, nil, tokens}

                 match = Regex.run(~r/^(--noora-[a-z0-9-]+):\s*(.*)$/, trimmed) ->
                   [_, name, value] = match
                   token = %{name: name, section: section, value: value}

                   if String.ends_with?(value, ";") do
                     {section, depth, nil, [%{token | value: String.trim_trailing(value, ";")} | tokens]}
                   else
                     {section, depth, token, tokens}
                   end

                 true ->
                   {section, depth, nil, tokens}
               end
             end)
             |> elem(3)
             |> Enum.reverse()
           end).()

  def all, do: @tokens

  @doc """
  Returns the tokens declared under the given section comments, in source order.
  """
  def section(names) when is_list(names), do: Enum.filter(@tokens, &(&1.section in names))
  def section(name), do: section([name])

  @doc """
  Returns the tokens whose name starts with the given prefix, in source order.
  """
  def prefixed(prefix), do: Enum.filter(@tokens, &String.starts_with?(&1.name, prefix))
end
