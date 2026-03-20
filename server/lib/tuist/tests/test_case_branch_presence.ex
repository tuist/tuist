defmodule Tuist.Tests.TestCaseBranchPresence do
  @moduledoc false
  use Ecto.Schema

  @primary_key false
  schema "test_case_branch_presence" do
    field :project_id, Ch, type: "Int64"
    field :git_branch, Ch, type: "String"
    field :is_ci, :boolean
    field :test_case_id, Ch, type: "Nullable(UUID)"
    field :ran_at, Ch, type: "DateTime64(6)"
  end
end
