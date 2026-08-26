defmodule Tuist.Kura.PlacerRegions do
  @moduledoc """
  The regions placement chose for an account, and the reads resolution and the
  lifecycle take against them.

  A primary row is the account's service region. Secondary rows are the extra
  regions sustained demand justified, and they serve alongside it. A row in
  `:retiring` still serves, and still holds its region against
  re-provisioning, until the drain that follows it finishes.
  """

  import Ecto.Query

  alias Tuist.Accounts.Account
  alias Tuist.Kura.PlacerRegion
  alias Tuist.Repo

  @doc """
  The regions the account should be running in, primary first. Empty when
  placement has never decided for it, which is every account until the placer
  or the pin-the-present backfill writes one.

  A retiring region is not one of them. It is still serving traffic until its
  drain starts, but nothing should provision it or hold its demand clock warm,
  or the lifecycle would rebuild the instance the retirement is removing.
  """
  def serving_regions(%Account{id: account_id}) do
    account_id
    |> rows_for()
    |> Enum.filter(&(&1.status == :desired))
    |> Enum.map(& &1.region)
  end

  @doc """
  Every region the account holds, retiring ones included. What placement reads,
  so it does not expand into a region it is in the middle of leaving.
  """
  def claimed_regions(%Account{id: account_id}) do
    account_id
    |> rows_for()
    |> Enum.map(& &1.region)
  end

  @doc """
  The account's regions that are on their way out.
  """
  def retiring_regions(%Account{id: account_id}) do
    account_id
    |> rows_for()
    |> Enum.filter(&(&1.status == :retiring))
    |> Enum.map(& &1.region)
  end

  @doc """
  The account's primary region, or `nil`.
  """
  def primary_region(%Account{id: account_id}) do
    case Repo.get_by(PlacerRegion, account_id: account_id, role: :primary) do
      nil -> nil
      %PlacerRegion{region: region} -> region
    end
  end

  @doc """
  Primary regions for many accounts at once, for the demand-flush hot path
  where the batch is every account that used the cache in the last minute.
  """
  def primary_regions(accounts) when is_list(accounts) do
    account_ids = Enum.map(accounts, & &1.id)

    PlacerRegion
    |> where([placer], placer.account_id in ^account_ids and placer.role == :primary)
    |> select([placer], {placer.account_id, placer.region})
    |> Repo.all()
    |> Map.new()
  end

  @doc """
  `serving_regions/1` for many accounts at once, in one query.
  """
  def serving_regions_all(accounts) when is_list(accounts) do
    account_ids = Enum.map(accounts, & &1.id)

    PlacerRegion
    |> where([placer], placer.account_id in ^account_ids and placer.status == :desired)
    |> order_by([placer], asc: placer.inserted_at, asc: placer.id)
    |> select([placer], {placer.account_id, placer.region})
    |> Repo.all()
    |> Enum.group_by(&elem(&1, 0), &elem(&1, 1))
  end

  @doc """
  Every placement row for the account, primary first then secondaries, each
  group oldest first so the order is total rather than whatever the database
  returns.
  """
  def all_for(%Account{id: account_id}), do: rows_for(account_id)

  @doc """
  Rows in `:retiring`, oldest first, capped at `limit`. What the lifecycle
  drains, once the account has somewhere else already serving.
  """
  def retiring(limit) do
    PlacerRegion
    |> where([placer], placer.status == :retiring)
    |> order_by([placer], asc: placer.updated_at, asc: placer.id)
    |> limit(^limit)
    |> preload(:account)
    |> Repo.all()
  end

  @doc """
  Makes `region` the account's primary, demoting whatever held the role. Runs
  inside the caller's transaction.

  The previous primary is demoted rather than deleted: a relocation leaves its
  source serving until the destination is up, and the row is what keeps it
  resolvable in the meantime.
  """
  def put_primary(%Account{id: account_id}, region, evidence \\ %{}) do
    PlacerRegion
    |> where([placer], placer.account_id == ^account_id and placer.role == :primary and placer.region != ^region)
    |> Repo.update_all(set: [role: :secondary, updated_at: DateTime.truncate(DateTime.utc_now(), :second)])

    upsert(account_id, region, %{role: :primary, status: :desired, evidence: evidence})
  end

  @doc """
  Adds `region` as a secondary the account serves alongside its primary.
  """
  def put_secondary(%Account{id: account_id}, region, evidence \\ %{}) do
    upsert(account_id, region, %{role: :secondary, status: :desired, evidence: evidence})
  end

  @doc """
  Marks `region` for retirement. It keeps serving and keeps holding the region
  until the lifecycle has drained it.

  Update-only: an account cannot be made to leave a region it does not hold,
  and creating a row to say so would invent a placement in the act of ending
  one — as a primary, since that is what a row defaults to.
  """
  def mark_retiring(%Account{id: account_id}, region, evidence \\ %{}) do
    case Repo.get_by(PlacerRegion, account_id: account_id, region: region) do
      nil ->
        {:error, :not_found}

      %PlacerRegion{} = existing ->
        existing
        |> PlacerRegion.changeset(%{status: :retiring, evidence: evidence})
        |> Repo.update()
    end
  end

  @doc """
  Drops the row once its region has been drained, so the region is free to be
  chosen again on its own merits.
  """
  def remove(%Account{id: account_id}, region) do
    PlacerRegion
    |> where([placer], placer.account_id == ^account_id and placer.region == ^region)
    |> Repo.delete_all()

    :ok
  end

  @doc """
  Writes rows for the regions an account is served from today, if it has none.

  What "pin the present" does for the running fleet, done for one account at
  the moment a decision is taken about it. Without it, applying a relocation
  to an account the backfill never reached would write the destination and
  leave the source with no row to retire, stranding it — the hazard that made
  pinning a precondition in the first place.
  """
  def materialize(%Account{id: account_id} = account, primary, serving) do
    case rows_for(account_id) do
      [] ->
        Enum.each(serving, fn region ->
          role = if region == primary, do: :primary, else: :secondary
          upsert(account_id, region, %{role: role, status: :desired, evidence: %{"signal" => "materialized"}})
        end)

      _rows ->
        :ok
    end

    account
  end

  defp rows_for(account_id) do
    PlacerRegion
    |> where([placer], placer.account_id == ^account_id)
    |> Repo.all()
    |> Enum.sort_by(&{&1.role != :primary, &1.inserted_at, &1.id})
  end

  defp upsert(account_id, region, attrs) do
    existing = Repo.get_by(PlacerRegion, account_id: account_id, region: region)

    changeset =
      PlacerRegion.changeset(
        existing || %PlacerRegion{},
        attrs |> Map.put(:account_id, account_id) |> Map.put(:region, region)
      )

    if existing, do: Repo.update(changeset), else: Repo.insert(changeset)
  end
end
