defmodule Tuist.Repo.Migrations.BackfillCommandEventsRemoteHitsCount do
  use Ecto.Migration
  import Ecto.Query

  @disable_ddl_transaction true
  @disable_migration_lock true
  @batch_size 1000
  @throttle_ms 100

  def up do
    alter table("command_events") do
      add_if_not_exists :remote_cache_hits_count_backfilled, :boolean, default: false
    end

    flush()

    try do
      throttle_change_in_batches(&page_query/1, &do_change/1)
    after
      alter table("command_events") do
        remove_if_exists :remote_cache_hits_count_backfilled, :boolean
      end
    end
  end

  def down, do: :ok

  def do_change(batch_of_ids) do
    # Wrap in a transaction to momentarily lock records during read/update
    repo().transaction(fn ->
      {_, results} =
        from(
          r in "command_events",
          where: r.id in ^batch_of_ids,
          select: r.id,
          update: [
            set: [
              remote_cache_hits_count_backfilled: true,
              remote_cache_target_hits_count:
                fragment("COALESCE(array_length(?, 1), 0)", r.remote_cache_target_hits),
              remote_test_target_hits_count:
                fragment("COALESCE(array_length(?, 1), 0)", r.remote_test_target_hits)
            ]
          ]
        )
        |> repo().update_all([])

      results
    end)
  end

  def page_query(last_id) do
    from(
      r in "command_events",
      select: r.id,
      where: r.id > ^last_id,
      where: r.remote_cache_hits_count_backfilled == false,
      order_by: [asc: r.id],
      limit: @batch_size
    )
  end

  # If you have BigInt IDs, fallback last_pod = 0
  # If you have UUID IDs, fallback last_pos = "00000000-0000-0000-0000-000000000000"
  # If you have Int IDs, you should consider updating it to BigInt or UUID :)
  defp throttle_change_in_batches(query_fun, change_fun, last_pos \\ 0)
  defp throttle_change_in_batches(_query_fun, _change_fun, nil), do: :ok

  defp throttle_change_in_batches(query_fun, change_fun, last_pos) do
    case repo().all(query_fun.(last_pos), log: :info, timeout: :infinity) do
      [] ->
        :ok

      ids ->
        case change_fun.(List.flatten(ids)) do
          {:ok, results} ->
            next_page = results |> Enum.reverse() |> List.first()
            Process.sleep(@throttle_ms)
            throttle_change_in_batches(query_fun, change_fun, next_page)

          error ->
            raise error
        end
    end
  end
end
