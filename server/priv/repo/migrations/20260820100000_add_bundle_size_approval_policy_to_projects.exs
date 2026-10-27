defmodule Tuist.Repo.Migrations.AddBundleSizeApprovalPolicyToProjects do
  use Ecto.Migration

  # Adding columns with defaults is safe on PostgreSQL 11+ (non-blocking)
  def change do
    alter table(:projects) do
      # excellent_migrations:safety-assured-for-next-line column_added_with_default
      add :bundle_size_approval_policy, :integer, default: 0, null: false
    end
  end
end
