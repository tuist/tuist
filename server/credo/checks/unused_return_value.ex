defmodule Credo.Checks.UnusedReturnValue do
  @moduledoc """
  Ensure that function return values are used or matched for configured modules.

  Certain operations can fail, and their return values should be checked
  to ensure errors are properly handled.
  """
  use Boundary
  use Credo.Check,
    base_priority: :high,
    category: :warning,
    param_defaults: [
      modules: [
        [:Tuist, :Repo],
        [:Tuist, :IngestRepo],
        [:Tuist, :ClickHouseRepo],
        [:Repo],
        [:IngestRepo],
        [:ClickHouseRepo],
        [:Oban]
      ],
      funs: ~w(
        insert insert_or_update
        update
        delete
        transaction
      )a,
      ignore: []
    ],
    explanations: [
      check: """
      Ensure that function return values are used or matched for configured modules.

      Certain operations can fail, and their return values should be checked
      to ensure errors are properly handled.
      """,
      params: [
        modules: "List of modules to check (as lists of atoms)",
        funs: "List of function names to check",
        ignore: "List of function names to ignore"
      ]
    ]

  alias Credo.Check.Warning.UnusedFunctionReturnHelper

  def run(%SourceFile{} = source_file, params \\ []) do
    modules = Params.get(params, :modules, __MODULE__)
    funs = Params.get(params, :funs, __MODULE__)
    ignored_funs = Params.get(params, :ignore, __MODULE__) |> List.wrap()
    issue_meta = IssueMeta.for(source_file, params)

    relevant_funs = funs -- ignored_funs

    modules
    |> Enum.flat_map(fn mod_list ->
      UnusedFunctionReturnHelper.find_unused_calls(
        source_file,
        params,
        mod_list,
        relevant_funs
      )
    end)
    |> Enum.map(&issue_for(&1, issue_meta))
  end

  defp issue_for(invalid_call, issue_meta) do
    {{:., _, [{:__aliases__, meta, mods}, _fun_name]}, _, _} = invalid_call

    module_name = Enum.join(mods, ".")

    trigger =
      invalid_call
      |> Macro.to_string()
      |> String.split("(")
      |> List.first()

    format_issue(
      issue_meta,
      message: "There should be no unused return values for #{module_name} functions.",
      trigger: trigger,
      line_no: meta[:line],
      column: meta[:column]
    )
  end
end
