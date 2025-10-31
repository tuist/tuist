defmodule Tuist.Repo.Migrations.ChangeRegionToEnumInAccounts do
  use Ecto.Migration

  def change do
    # No migration needed - the database column remains as integer
    # Ecto.Enum with integer values works with existing integer column
  end
end
