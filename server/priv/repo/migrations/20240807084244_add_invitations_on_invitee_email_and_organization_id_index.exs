defmodule Tuist.Repo.Migrations.AddInvitationsOnInviteeEmailAndOrganizationIdIndex do
  use Ecto.Migration
  @disable_ddl_transaction true
  @disable_migration_lock true

  def up do
    drop unique_index(:invitations, [:invitee_email, :organization_id],
           name: "index_invitations_on_invitee_email_and_organization_id"
         )

    create unique_index(:invitations, [:invitee_email, :organization_id])
  end

  def down do
    drop unique_index(:invitations, [:invitee_email, :organization_id])

    create unique_index(:invitations, [:invitee_email, :organization_id],
             name: "index_invitations_on_invitee_email_and_organization_id"
           )
  end
end
