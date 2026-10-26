defmodule Tuist.Repo.Migrations.AddTestContextToOnceRuns do
  @moduledoc false
  use Ecto.Migration

  def change do
    alter table(:once_runs) do
      add :test_context, :map, default: %{}, null: false
    end
  end
end
