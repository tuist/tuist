defmodule Tuist.Tests.TestCaseRunProject do
  @moduledoc false

  use Ecto.Schema

  @primary_key {:id, Ecto.UUID, autogenerate: false}
  schema "test_case_run_projects" do
    field :project_id, Ch, type: "Int64"
    field :inserted_at, Ch, type: "DateTime64(6)"
  end
end
