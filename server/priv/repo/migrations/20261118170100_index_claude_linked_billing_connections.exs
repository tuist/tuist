defmodule Tuist.Repo.Migrations.IndexClaudeLinkedBillingConnections do
  use Ecto.Migration

  @disable_ddl_transaction true
  @disable_migration_lock true

  # An organization links at most one Claude organization.
  def change do
    create unique_index(:organization_ai_connections, [:organization_id],
             where: "kind = 'claude_linked_billing'",
             name: :organization_ai_connections_claude_linked_billing_index,
             concurrently: true
           )
  end
end
