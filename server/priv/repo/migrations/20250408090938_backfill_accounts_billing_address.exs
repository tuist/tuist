defmodule Tuist.Repo.Migrations.BackfillAccountsBillingAddress do
  @moduledoc ~S"""
  The backfilling of accounts.billing_email had a bug, causing some accounts to have a wrong billing_email.
  This is a new migration that ensures we pick the right email based on the account type:
  - User account: The user email.
  - Organization account: The email of the first admin.
  """
  use Ecto.Migration
  import Ecto.Query
  alias Tuist.Repo

  @disable_ddl_transaction true
  @disable_migration_lock true

  def change do
    all_accounts_query =
      from(a in "accounts",
        select: %{id: a.id, organization_id: a.organization_id, user_id: a.user_id}
      )

    # excellent_migrations:safety-assured-for-next-line operation_all
    for account <- Repo.all(all_accounts_query) do
      backfill(account)
    end
  end

  defp backfill(%{organization_id: organization_id, id: account_id})
       when not is_nil(organization_id) do
    billing_email =
      from(ur in "users_roles",
        join: r in "roles",
        on: ur.role_id == r.id,
        join: u in "users",
        on: ur.user_id == u.id,
        where:
          r.name == "admin" and r.resource_type == "Organization" and
            r.resource_id == ^organization_id,
        order_by: [asc: ur.created_at],
        select: u.email,
        limit: 1
      )
      # excellent_migrations:safety-assured-for-next-line operation_one
      |> Repo.one!()

    # excellent_migrations:safety-assured-for-next-line operation_update
    Repo.update_all(from(a in "accounts", where: a.id == ^account_id),
      set: [billing_email: billing_email]
    )
  end

  defp backfill(%{user_id: user_id, id: account_id}) when not is_nil(user_id) do
    billing_email_query = from(u in "users", where: u.id == ^user_id, select: u.email, limit: 1)
    # excellent_migrations:safety-assured-for-next-line operation_one
    billing_email = Repo.one!(billing_email_query)

    # excellent_migrations:safety-assured-for-next-line operation_update
    Repo.update_all(from(a in "accounts", where: a.id == ^account_id),
      set: [billing_email: billing_email]
    )
  end
end
