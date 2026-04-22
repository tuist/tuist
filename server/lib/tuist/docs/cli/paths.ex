defmodule Tuist.Docs.CLI.Paths do
  @moduledoc """
  Canonical paths and redirect rules for CLI documentation.

  This keeps CLI-specific URL knowledge close to the CLI docs subsystem so
  other modules can depend on it without turning generic redirect logic into
  a CLI registry.
  """

  @base_path "/references/cli"
  @commands_base_path @base_path <> "/commands"
  @static_pages [
    {"debugging", "Debugging"},
    {"directories", "Directories"},
    {"shell-completions", "Shell completions"}
  ]
  @static_slugs Enum.map(@static_pages, &elem(&1, 0))

  @doc "Logical path under `/docs/` where hand-written CLI pages live."
  def base_path, do: @base_path

  @doc "Logical path under `/docs/` where auto-generated CLI command pages live."
  def commands_base_path, do: @commands_base_path

  @doc """
  Hand-written CLI pages as `{slug_segment, english_label}` tuples.

  The English label is the source string that flows through the
  `priv/docs/strings/*.json` translation map at render time.
  """
  def static_pages, do: @static_pages

  @doc "Slug fragments under `base_path/` served by hand-written pages (not commands)."
  def static_slugs, do: @static_slugs

  @doc """
  Full English slug (i.e. with the `/en` locale prefix) for a hand-written CLI page.
  """
  def page_slug(segment), do: "/en" <> @base_path <> "/" <> segment

  @doc """
  Full English slug for an auto-generated CLI command page.

  Accepts either the command name (`"generate"`) or a full path (`"cache/warm"`).
  """
  def command_slug(command_path), do: "/en" <> @commands_base_path <> "/" <> command_path

  @doc """
  Redirect rules for CLI docs.

  Rules operate on the portion of the path after `/<locale>/docs`, i.e. the
  logical docs path that always starts with "/".
  """
  def redirect_rules do
    [
      {:exact, "/cli", @base_path},
      {:prefix, "/cli/", @base_path <> "/"},
      {:prefix, @base_path <> "/", @commands_base_path <> "/", except_starts_with: @static_slugs ++ ["commands/"]}
    ]
  end
end
