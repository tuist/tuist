defmodule Tuist.ClickHouseRepo.Migrations.AddIndexesToXcodeTargets do
  use Ecto.Migration

  def change do
    #
    # 1. Sub-string search on `name`
    #
    # excellent_migrations:safety-assured-for-next-line raw_sql_executed
    execute(
      "ALTER TABLE xcode_targets ADD INDEX idx_name_ngram name TYPE ngrambf_v1(3, 256, 2, 0) GRANULARITY 4",
      "ALTER TABLE xcode_targets DROP INDEX idx_name_ngram"
    )

    #
    # 2. Exact / IN lookup on hash columns
    #
    # excellent_migrations:safety-assured-for-next-line raw_sql_executed
    execute(
      "ALTER TABLE xcode_targets ADD INDEX idx_selective_testing_hash selective_testing_hash TYPE bloom_filter(0.01) GRANULARITY 4",
      "ALTER TABLE xcode_targets DROP INDEX idx_selective_testing_hash"
    )

    # excellent_migrations:safety-assured-for-next-line raw_sql_executed
    execute(
      "ALTER TABLE xcode_targets ADD INDEX idx_binary_cache_hash binary_cache_hash TYPE bloom_filter(0.01) GRANULARITY 4",
      "ALTER TABLE xcode_targets DROP INDEX idx_binary_cache_hash"
    )
  end
end
