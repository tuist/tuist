defmodule Tuist.Repo.Migrations.BackfillAccountBillingEmail do
  use Ecto.Migration
  import Ecto.Query

  @disable_ddl_transaction true
  @disable_migration_lock true

  @disable_ddl_transaction true
  @disable_migration_lock true
  @batch_size 1000
  @throttle_ms 100

  def up do
    throttle_change_in_batches(&page_query/1, &do_change/1)
  end

  def down, do: :ok

  def do_change(batch_of_ids) do
    # For the accounts identified by the ids in batch_of_ids with get the email address:
    # - User accounts: The email of the user associated with the account
    # - Organization accounts: The email of the first admin user associated with the organization
    email_mappings =
      from(a in "accounts",
        where: a.id in ^batch_of_ids,
        left_join: direct_usr in "users",
        on: a.user_id == direct_usr.id,
        left_join: u in "users_roles",
        left_join: r in "roles",
        on:
          u.role_id == r.id and
            r.name == "admin" and
            r.resource_type == "Organization" and
            r.resource_id == a.organization_id,
        left_join: admin_usr in "users",
        on: u.user_id == admin_usr.id,
        order_by: [asc: u.created_at],
        select: {a.id, fragment("COALESCE(?, ?)", direct_usr.email, admin_usr.email)}
      )
      |> repo().all()
      |> Enum.reject(fn {_, email} -> is_nil(email) end)
      |> Map.new()

    results =
      Enum.map(batch_of_ids, fn account_id ->
        # We update accounts one by one because we can't use "update_all" with a dynamic
        # value.
        {_count, [updated_id]} =
          repo().update_all(
            from(a in "accounts",
              where: a.id == ^account_id,
              select: a.id
            ),
            [set: [billing_email: Map.fetch!(email_mappings, account_id)]],
            log: :info
          )

        updated_id
      end)

    not_updated =
      MapSet.difference(MapSet.new(batch_of_ids), MapSet.new(results))
      |> MapSet.to_list()

    Enum.each(not_updated, &handle_non_update/1)
    results
  end

  def page_query(last_id) do
    from(
      a in "accounts",
      select: a.id,
      where: is_nil(a.billing_email) and a.id > ^last_id,
      order_by: [asc: a.id],
      limit: @batch_size
    )
  end

  # If you have BigInt or Int IDs, fallback last_pos = 0
  # If you have UUID IDs, fallback last_pos = "00000000-0000-0000-0000-000000000000"
  defp throttle_change_in_batches(query_fun, change_fun, last_pos \\ 0)
  defp throttle_change_in_batches(_query_fun, _change_fun, nil), do: :ok

  defp throttle_change_in_batches(query_fun, change_fun, last_pos) do
    case repo().all(query_fun.(last_pos), log: :info, timeout: :infinity) do
      [] ->
        :ok

      ids ->
        results = change_fun.(List.flatten(ids))
        next_page = results |> Enum.reverse() |> List.first()
        Process.sleep(@throttle_ms)
        throttle_change_in_batches(query_fun, change_fun, next_page)
    end
  end

  defp handle_non_update(id) do
    raise "#{inspect(id)} was not updated"
  end
end
