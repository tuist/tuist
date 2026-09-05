defmodule Tuist.Repo.Migrations.AddStressNewTestsParametersToProjects do
  use Ecto.Migration

  @default_curve ~s([{"max_duration_ms":5000,"repetitions":10},{"max_duration_ms":10000,"repetitions":5},{"max_duration_ms":30000,"repetitions":3},{"max_duration_ms":300000,"repetitions":2}])

  def up do
    alter table(:projects) do
      # Constant defaults are stored in the catalog rather than rewriting the
      # table, so existing projects pick up the fleet-measured values without
      # a backfill.
      # excellent_migrations:safety-assured-for-next-line column_added_with_default
      add :stress_new_tests_repetition_curve, :map,
        null: false,
        default: fragment("'#{@default_curve}'::jsonb")

      # excellent_migrations:safety-assured-for-next-line column_added_with_default
      add :stress_new_tests_candidate_cap, :integer, null: false, default: 200
      # excellent_migrations:safety-assured-for-next-line column_added_with_default
      add :stress_new_tests_wall_clock_ceiling_ms, :integer, null: false, default: 600_000
      # excellent_migrations:safety-assured-for-next-line column_added_with_default
      add :stress_new_tests_bulk_change_ratio, :float, null: false, default: 0.3
      # excellent_migrations:safety-assured-for-next-line column_added_with_default
      add :stress_new_tests_bulk_change_floor, :integer, null: false, default: 50
    end
  end

  def down do
    alter table(:projects) do
      # excellent_migrations:safety-assured-for-next-line column_removed
      remove :stress_new_tests_repetition_curve
      # excellent_migrations:safety-assured-for-next-line column_removed
      remove :stress_new_tests_candidate_cap
      # excellent_migrations:safety-assured-for-next-line column_removed
      remove :stress_new_tests_wall_clock_ceiling_ms
      # excellent_migrations:safety-assured-for-next-line column_removed
      remove :stress_new_tests_bulk_change_ratio
      # excellent_migrations:safety-assured-for-next-line column_removed
      remove :stress_new_tests_bulk_change_floor
    end
  end
end
