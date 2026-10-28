defmodule Tuist.Tests.TestSelectionDecision do
  @moduledoc """
  What a test selection plan (`Tuist.Tests.TestSelection`) decided for one
  test (`scope_kind` `test`: module, suite and name) or one test target
  (`scope_kind` `target`: the module) of a scheme: `selected` or `skipped`,
  and why (`reason`). `covered_paths` are the repository files the
  baseline's evidence says it executed, `changed_paths` the ones among them
  that changed since, `source_path` the file the test or target is declared
  in, and `duration` how long it took in the baseline, in milliseconds. This
  is a ClickHouse entity.
  """
  use Ecto.Schema

  @primary_key {:id, Ecto.UUID, autogenerate: false}
  schema "test_selection_decisions" do
    field :test_selection_id, Ch, type: "UUID"
    field :project_id, Ch, type: "Int64"
    field :scheme, Ch, type: "String"
    field :scope_kind, Ch, type: "LowCardinality(String)"
    field :module_name, Ch, type: "String"
    field :suite_name, Ch, type: "String"
    field :name, Ch, type: "String"
    field :test_case_id, Ch, type: "Nullable(UUID)"
    field :source_path, Ch, type: "String"
    field :decision, Ch, type: "LowCardinality(String)"
    field :reason, Ch, type: "LowCardinality(String)"
    field :covered_paths, Ch, type: "Array(String)"
    field :changed_paths, Ch, type: "Array(String)"
    field :evidence_test_run_id, Ch, type: "Nullable(UUID)"
    field :duration, Ch, type: "UInt32"
    field :inserted_at, Ch, type: "DateTime64(6)"
  end
end
