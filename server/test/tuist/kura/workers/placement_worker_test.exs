defmodule Tuist.Kura.Workers.PlacementWorkerTest do
  use TuistTestSupport.Cases.DataCase, async: false

  import Mimic

  alias Tuist.Accounts
  alias Tuist.Environment
  alias Tuist.Kura.OriginRollup
  alias Tuist.Kura.PlacementProposal
  alias Tuist.Kura.PlacementProposals
  alias Tuist.Kura.PlacerRegions
  alias Tuist.Kura.Server
  alias Tuist.Kura.Workers.PlacementWorker
  alias Tuist.Repo
  alias TuistTestSupport.Fixtures.AccountsFixtures
  alias TuistTestSupport.Fixtures.BillingFixtures

  setup :set_mimic_from_context

  setup do
    stub(Environment, :tuist_hosted?, fn -> true end)
    stub(Environment, :dev?, fn -> false end)
    stub(Environment, :test?, fn -> false end)
    stub(Environment, :kura_available_region_ids, fn -> ["us-east", "eu-central"] end)

    :ok
  end

  test "opens proposals and applies nothing while the budget is zero" do
    # The supervised phase: placement proposes, an operator applies. Raising
    # the budget is what graduates it, which is a configuration change rather
    # than a different code path.
    stub(Environment, :kura_placement_automatic_applies_per_day, fn -> 0 end)
    account = account_with_moved_traffic()

    assert :ok = perform_job(PlacementWorker, %{})

    assert %PlacementProposal{status: :open} = PlacementProposals.open_proposal_for(account)
    assert PlacerRegions.primary_region(account) == nil
  end

  test "applies within the budget once it is raised" do
    stub(Environment, :kura_placement_automatic_applies_per_day, fn -> 1 end)
    account = account_with_moved_traffic()

    assert :ok = perform_job(PlacementWorker, %{})

    assert PlacementProposals.open_proposal_for(account) == nil
    assert PlacerRegions.primary_region(account) == "eu-central"

    applied = Repo.get_by!(PlacementProposal, account_id: account.id, status: :applied)
    assert applied.resolved_by == "automatic"
  end

  test "stops at the budget rather than moving every account it could" do
    stub(Environment, :kura_placement_automatic_applies_per_day, fn -> 1 end)
    first = account_with_moved_traffic()
    second = account_with_moved_traffic()

    assert :ok = perform_job(PlacementWorker, %{})

    applied =
      [first, second]
      |> Enum.map(&PlacerRegions.primary_region/1)
      |> Enum.count(&(&1 == "eu-central"))

    assert applied == 1
  end

  test "spends the budget over a trailing day rather than per pass" do
    # A rate, not a per-pass count, so changing the cadence cannot multiply how
    # much the fleet moves in a day.
    stub(Environment, :kura_placement_automatic_applies_per_day, fn -> 1 end)
    first = account_with_moved_traffic()
    second = account_with_moved_traffic()

    assert :ok = perform_job(PlacementWorker, %{})
    assert :ok = perform_job(PlacementWorker, %{})

    applied =
      [first, second]
      |> Enum.map(&PlacerRegions.primary_region/1)
      |> Enum.count(&(&1 == "eu-central"))

    assert applied == 1
  end

  defp account_with_moved_traffic do
    user = AccountsFixtures.user_fixture()
    account = Accounts.get_account_from_user(user)
    BillingFixtures.subscription_fixture(account_id: account.id, plan: :pro)

    %Server{}
    |> Server.create_changeset(%{
      account_id: account.id,
      region: "us-east",
      provisioner_node_ref: "kura-#{account.name}-us-east"
    })
    |> Repo.insert!()

    now = DateTime.truncate(DateTime.utc_now(), :second)
    today = Date.utc_today()

    Repo.insert_all(
      OriginRollup,
      for offset <- 0..29 do
        %{
          account_id: account.id,
          origin: "FR",
          date: Date.add(today, -offset),
          run_count: 20,
          demand_count: 0,
          inserted_at: now,
          updated_at: now
        }
      end
    )

    account
  end
end
