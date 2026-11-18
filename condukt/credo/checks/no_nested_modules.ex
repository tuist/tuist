defmodule Condukt.Credo.Check.Readability.NoNestedModules do
  use Credo.Check,
    id: "EXC001",
    base_priority: :high,
    category: :readability,
    explanations: [
      check: """
      Nested modules in production code should be extracted into their own files.

          # preferred

          defmodule MyApp.Parent do
            alias MyApp.Parent.Child
          end

          defmodule MyApp.Parent.Child do
          end

      This keeps the file layout aligned with the module tree and makes nested
      helper modules easier to find, review, and reuse.
      """
    ]

  alias Credo.IssueMeta
  alias Credo.SourceFile

  @impl true
  def run(%SourceFile{filename: filename} = source_file, params \\ []) do
    if lib_file?(filename) do
      issue_meta = IssueMeta.for(source_file, params)

      source_file
      |> Credo.Code.ast()
      |> Credo.Code.Module.analyze()
      |> Enum.flat_map(&issues_for_module(&1, issue_meta))
    else
      []
    end
  end

  defp lib_file?(filename) do
    String.starts_with?(filename, "lib/") or String.contains?(filename, "/lib/")
  end

  defp issues_for_module({_module, parts}, issue_meta) do
    parts
    |> Enum.filter(fn {part, _meta} -> part == :module end)
    |> Enum.map(fn {_part, meta} -> issue_for(issue_meta, meta) end)
  end

  defp issue_for(issue_meta, meta) do
    format_issue(
      issue_meta,
      message: "Nested modules in lib files should be extracted into their own files.",
      trigger: "defmodule",
      line_no: Keyword.get(meta, :line)
    )
  end
end
