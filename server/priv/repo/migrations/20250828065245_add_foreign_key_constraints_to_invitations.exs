defmodule Tuist.Repo.Migrations.AddForeignKeyConstraintsToInvitations do
  use Ecto.Migration

  def up do
    # Clean up any orphaned invitation records before adding constraints
    # Delete invitations where inviter_id references non-existent users
    execute """
    DELETE FROM invitations 
    WHERE inviter_id IS NOT NULL 
    AND NOT EXISTS (
      SELECT 1 FROM users WHERE id = invitations.inviter_id
    )
    """

    # Delete invitations where organization_id references non-existent organizations
    execute """
    DELETE FROM invitations 
    WHERE organization_id IS NOT NULL 
    AND NOT EXISTS (
      SELECT 1 FROM organizations WHERE id = invitations.organization_id
    )
    """

    # Add foreign key constraint for inviter_id -> users.id with cascade delete
    alter table(:invitations) do
      modify :inviter_id, references(:users, on_delete: :delete_all),
        null: false,
        from: {:bigint, null: false}
    end

    # Add foreign key constraint for organization_id -> organizations.id with cascade delete  
    alter table(:invitations) do
      modify :organization_id, references(:organizations, on_delete: :delete_all),
        null: false,
        from: {:bigint, null: false}
    end
  end

  def down do
    # Remove foreign key constraints
    alter table(:invitations) do
      modify :inviter_id, :bigint, null: false
    end

    alter table(:invitations) do
      modify :organization_id, :bigint, null: false
    end
  end
end
