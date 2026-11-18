defmodule TuistOps.Repo.Migrations.DropPreviews do
  use Ecto.Migration

  # The Slack `/preview` flow and the preview cluster it deployed to are gone,
  # so nothing reads or writes these audit rows anymore.
  def up do
    drop_if_exists table(:previews)
  end

  def down do
    raise Ecto.MigrationError, "the previews table is not restored on rollback"
  end
end
