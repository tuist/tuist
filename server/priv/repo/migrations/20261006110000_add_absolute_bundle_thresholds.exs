defmodule Tuist.Repo.Migrations.AddAbsoluteBundleThresholds do
  use Ecto.Migration

  def up do
    alter table(:bundle_thresholds) do
      # Only relax nullability; the existing float8 values and type are unchanged.
      # excellent_migrations:safety-assured-for-next-line column_type_changed
      modify :deviation_percentage, :float, null: true
      add :deviation_bytes, :bigint
    end

    # Configuration table with at most a handful of rules per project.
    # excellent_migrations:safety-assured-for-next-line check_constraint_added
    create constraint(:bundle_thresholds, :bundle_thresholds_one_limit,
             check: "(deviation_percentage IS NOT NULL) <> (deviation_bytes IS NOT NULL)"
           )
  end

  def down do
    # Refuse to discard absolute rules or invent percentages without a baseline.
    # excellent_migrations:safety-assured-for-next-line raw_sql_executed
    execute """
    DO $$ BEGIN
      IF EXISTS (SELECT 1 FROM bundle_thresholds WHERE deviation_bytes IS NOT NULL) THEN
        RAISE EXCEPTION 'Convert absolute bundle thresholds to percentages before rolling back';
      END IF;
    END $$;
    """

    drop constraint(:bundle_thresholds, :bundle_thresholds_one_limit)

    alter table(:bundle_thresholds) do
      # The guard guarantees no byte limits remain to discard.
      # excellent_migrations:safety-assured-for-next-line column_removed
      remove :deviation_bytes
      # The guard and constraint guarantee every remaining row has a percentage.
      # excellent_migrations:safety-assured-for-next-line column_type_changed not_null_added
      modify :deviation_percentage, :float, null: false
    end
  end
end
