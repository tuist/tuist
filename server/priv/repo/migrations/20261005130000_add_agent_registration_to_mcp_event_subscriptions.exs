defmodule Tuist.Repo.Migrations.AddAgentRegistrationToMcpEventSubscriptions do
  use Ecto.Migration

  def up do
    alter table(:mcp_event_subscriptions) do
      add :agent_registration_id,
          references(:agent_registrations, type: :uuid, on_delete: :delete_all)
    end

    # excellent_migrations:safety-assured-for-next-line index_not_concurrently
    create index(:mcp_event_subscriptions, [:agent_registration_id])

    drop constraint(:mcp_event_subscriptions, :one_credential)

    # excellent_migrations:safety-assured-for-next-line check_constraint_added
    create constraint(:mcp_event_subscriptions, :one_credential,
             check:
               "(account_token_id IS NOT NULL AND agent_registration_id IS NULL AND oauth_client_id IS NULL AND oauth_grant_id IS NULL) OR " <>
                 "(account_token_id IS NULL AND agent_registration_id IS NOT NULL AND oauth_client_id IS NULL AND oauth_grant_id IS NULL) OR " <>
                 "(account_token_id IS NULL AND agent_registration_id IS NULL AND oauth_client_id IS NOT NULL AND oauth_grant_id IS NOT NULL)"
           )
  end

  def down do
    drop constraint(:mcp_event_subscriptions, :one_credential)

    # excellent_migrations:safety-assured-for-next-line check_constraint_added
    create constraint(:mcp_event_subscriptions, :one_credential,
             check:
               "(account_token_id IS NOT NULL AND oauth_client_id IS NULL AND oauth_grant_id IS NULL) OR " <>
                 "(account_token_id IS NULL AND oauth_client_id IS NOT NULL AND oauth_grant_id IS NOT NULL)"
           )

    # excellent_migrations:safety-assured-for-next-line index_not_concurrently
    drop index(:mcp_event_subscriptions, [:agent_registration_id])

    alter table(:mcp_event_subscriptions) do
      # excellent_migrations:safety-assured-for-next-line column_removed
      remove :agent_registration_id
    end
  end
end
