defmodule Atlas.Repo.Migrations.NormalizeProductChangelogEntriesTable do
  use Ecto.Migration

  def up do
    execute """
    DO $$
    BEGIN
      IF to_regclass('product_changelog_entries') IS NULL
         AND to_regclass('product_features') IS NOT NULL THEN
        ALTER TABLE product_features RENAME TO product_changelog_entries;
      END IF;

      IF to_regclass('product_changelog_entries') IS NOT NULL THEN
        IF EXISTS (
          SELECT 1
          FROM information_schema.columns
          WHERE table_name = 'product_changelog_entries'
            AND column_name = 'feature_id'
        ) THEN
          ALTER TABLE product_changelog_entries RENAME COLUMN feature_id TO entry_id;
        END IF;

        IF EXISTS (
          SELECT 1
          FROM information_schema.columns
          WHERE table_name = 'product_changelog_entries'
            AND column_name = 'domain'
        ) AND NOT EXISTS (
          SELECT 1
          FROM information_schema.columns
          WHERE table_name = 'product_changelog_entries'
            AND column_name = 'domains'
        ) THEN
          ALTER TABLE product_changelog_entries
            ADD COLUMN domains varchar[] NOT NULL DEFAULT '{}';

          UPDATE product_changelog_entries
          SET domains = ARRAY[domain]
          WHERE domain IS NOT NULL AND domain != '';

          ALTER TABLE product_changelog_entries DROP COLUMN domain;
        ELSIF NOT EXISTS (
          SELECT 1
          FROM information_schema.columns
          WHERE table_name = 'product_changelog_entries'
            AND column_name = 'domains'
        ) THEN
          ALTER TABLE product_changelog_entries
            ADD COLUMN domains varchar[] NOT NULL DEFAULT '{}';
        END IF;
      END IF;
    END
    $$;
    """

    execute "DROP INDEX IF EXISTS product_features_feature_id_index"
    execute "DROP INDEX IF EXISTS product_features_source_guid_index"
    execute "DROP INDEX IF EXISTS product_features_domain_index"
    execute "DROP INDEX IF EXISTS product_features_release_date_index"

    execute "CREATE UNIQUE INDEX IF NOT EXISTS product_changelog_entries_entry_id_index ON product_changelog_entries (entry_id)"

    execute "CREATE UNIQUE INDEX IF NOT EXISTS product_changelog_entries_source_guid_index ON product_changelog_entries (source_guid)"

    execute "CREATE INDEX IF NOT EXISTS product_changelog_entries_domains_index ON product_changelog_entries USING gin (domains)"

    execute "CREATE INDEX IF NOT EXISTS product_changelog_entries_release_date_index ON product_changelog_entries (release_date)"
  end

  def down do
    :ok
  end
end
