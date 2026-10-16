# SQL only targets a connection-local temporary table inside a sandbox transaction.
# excellent_migrations:safety-assured-for-this-file operation_query operation_config
Code.require_file(
  Path.expand("../../../../priv/repo/migrations/20261006110000_add_absolute_bundle_thresholds.exs", __DIR__)
)

defmodule Tuist.Repo.Migrations.AddAbsoluteBundleThresholdsTest do
  use TuistTestSupport.Cases.DataCase, async: true

  alias Ecto.Migration.Runner
  alias Tuist.Repo
  alias Tuist.Repo.Migrations.AddAbsoluteBundleThresholds

  setup do
    Repo.query!("""
    CREATE TEMP TABLE bundle_thresholds (
      id integer PRIMARY KEY,
      deviation_percentage double precision NOT NULL
    )
    """)

    :ok
  end

  test "preserves legacy percentages through migration and rollback" do
    for {percentage, id} <- Enum.with_index([5.0, 0.47, 0.00001], 1) do
      Repo.query!("INSERT INTO pg_temp.bundle_thresholds VALUES ($1, $2)", [id, percentage])
    end

    migrate(:up)

    assert Repo.query!("SELECT deviation_percentage, deviation_bytes FROM pg_temp.bundle_thresholds ORDER BY id").rows ==
             [[5.0, nil], [0.47, nil], [0.00001, nil]]

    # Old code can still write percentage-only rules after the migration.
    Repo.query!("INSERT INTO pg_temp.bundle_thresholds (id, deviation_percentage) VALUES (4, 0.15)")
    migrate(:down)

    assert Repo.query!("SELECT deviation_percentage FROM pg_temp.bundle_thresholds ORDER BY id").rows ==
             [[5.0], [0.47], [0.00001], [0.15]]
  end

  test "refuses rollback without discarding an absolute rule" do
    migrate(:up)
    Repo.query!("INSERT INTO pg_temp.bundle_thresholds (id, deviation_bytes) VALUES (1, 1500000)")

    assert_raise Postgrex.Error, ~r/Convert absolute bundle thresholds to percentages before rolling back/, fn ->
      migrate(:down)
    end

    assert Repo.query!("SELECT deviation_percentage, deviation_bytes FROM pg_temp.bundle_thresholds").rows ==
             [[nil, 1_500_000]]

    Repo.query!("UPDATE pg_temp.bundle_thresholds SET deviation_bytes = NULL, deviation_percentage = 0.47")
    migrate(:down)
    assert Repo.query!("SELECT deviation_percentage FROM pg_temp.bundle_thresholds").rows == [[0.47]]
  end

  defp migrate(direction) do
    Runner.run(Repo, Repo.config(), 20_261_006_110_000, AddAbsoluteBundleThresholds, :forward, direction, direction,
      prefix: "pg_temp",
      log: false
    )
  end
end
