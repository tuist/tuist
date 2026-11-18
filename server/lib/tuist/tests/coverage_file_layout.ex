defmodule Tuist.Tests.CoverageFileLayout do
  @moduledoc """
  A version of a source file as coverage reports describe it: its blob, its
  executable lines (`line_numbers`, ascending) and its functions (name, first
  line and executable lines, index by index). Runs of the same version report
  the same layout, so it is stored once per project and week (`epoch`, the
  first day of the week of the reports that use it, which each path starts on
  its own weekday: `Tuist.Tests.Coverage.layout_epoch/2`) and each
  `Tuist.Tests.CoverageRunFile`
  names it by `layout_id`, a hash of the path and the rest that is only
  required to be unique per path. A week's layouts expire together, after
  every run row that names them.
  """
  use Ecto.Schema

  @primary_key false
  schema "coverage_file_layouts" do
    field :project_id, Ch, type: "Int64"
    field :epoch, :date
    field :path, Ch, type: "String"
    field :layout_id, Ch, type: "UInt32"
    field :git_blob_id, Ch, type: "String", default: ""
    field :line_numbers, Ch, type: "Array(UInt32)"
    field :function_names, Ch, type: "Array(String)"
    field :function_line_numbers, Ch, type: "Array(UInt32)"
    field :function_executable_lines, Ch, type: "Array(UInt32)"
  end
end
