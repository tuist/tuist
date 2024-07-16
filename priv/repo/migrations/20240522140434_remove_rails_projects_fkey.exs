defmodule Tuist.Repo.Migrations.RemoveRailsProjectsFkey do
  use Ecto.Migration

  def up do
    # Drop projects_account_id_fkey
    # This foreign key is redundant due to `AddDeleteAllReferences` migration
    drop constraint(:projects, "fk_rails_b4884d7210")
  end
end
