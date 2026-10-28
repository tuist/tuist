defmodule Tuist.Tests.TestSelectionChangedFile do
  @moduledoc """
  A file that changed between a test selection plan's baseline and its
  commit (`Tuist.Tests.TestSelection`): its `status` (`added`, `modified`
  or `deleted`), its `kind` (`source`, `test`, `resource`, `tracked` or
  `ignored`) and how many of the plan's tests or targets it selected. This
  is a ClickHouse entity.
  """
  use Ecto.Schema

  @primary_key false
  schema "test_selection_changed_files" do
    field :test_selection_id, Ch, type: "UUID"
    field :project_id, Ch, type: "Int64"
    field :path, Ch, type: "String"
    field :status, Ch, type: "LowCardinality(String)"
    field :kind, Ch, type: "LowCardinality(String)"
    field :selected_count, Ch, type: "UInt32"
    field :inserted_at, Ch, type: "DateTime64(6)"
  end
end
