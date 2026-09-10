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
    stub(Environment, :kura_available_region_ids, fn -> ["us-east", "eu-west"] end)

    :ok
  end

  test "opens proposals and applies nothing while every budget is zero" do
    # The supervised phase: placement proposes, an operator applies. Raising a
    # budget is what graduates it, which is a configuration change rather than
    # a different code path.
    stub_budgets(%{})
    account = account_with_moved_traffic()

    assert :ok = perform_job(PlacementWorker, %{})

    assert %PlacementProposal{status: :open} = PlacementProposals.open_proposal_for(account)
    assert PlacerRegions.primary_region(account) == nil
  end

  test "applies within the budget once the kind is raised" do
    stub_budgets(%{correct: 1})
    account = account_with_moved_traffic()

    assert :ok = perform_job(PlacementWorker, %{})

    assert PlacementProposals.open_proposal_for(account) == nil
    assert PlacerRegions.primary_region(account) == "eu-west"

    applied = Repo.get_by!(PlacementProposal, account_id: account.id, status: :applied)
    assert applied.resolved_by == "automatic"
  end

  test "leaves a kind alone while another kind is draining" do
    # The budget is what says a kind may run unattended. A number raised for
    # the additive kind cannot be spent by the kind that gives a region up.
    stub_budgets(%{expand: 5})
    account = account_with_moved_traffic()

    assert :ok = perform_job(PlacementWorker, %{})

    assert %PlacementProposal{status: :open, kind: :correct} = PlacementProposals.open_proposal_for(account)
    assert PlacerRegions.primary_region(account) == nil
  end

  test "stops at the budget rather than moving every account it could" do
    stub_budgets(%{correct: 1})
    first = account_with_moved_traffic()
    second = account_with_moved_traffic()

    assert :ok = perform_job(PlacementWorker, %{})

    applied =
      [first, second]
      |> Enum.map(&PlacerRegions.primary_region/1)
      |> Enum.count(&(&1 == "eu-west"))

    assert applied == 1
  end

  test "spends the budget over a trailing day rather than per pass" do
    # A rate, not a per-pass count, so changing the cadence cannot multiply how
    # much the fleet moves in a day.
    stub_budgets(%{correct: 1})
    first = account_with_moved_traffic()
    second = account_with_moved_traffic()

    assert :ok = perform_job(PlacementWorker, %{})
    assert :ok = perform_job(PlacementWorker, %{})

    applied =
      [first, second]
      |> Enum.map(&PlacerRegions.primary_region/1)
      |> Enum.count(&(&1 == "eu-west"))

    assert applied == 1
  end

  test "one kind's spend does not draw down another kind's budget" do
    stub_budgets(%{correct: 1, expand: 1})
    first = account_with_moved_traffic()
    second = account_with_moved_traffic()

    assert :ok = perform_job(PlacementWorker, %{})
    assert :ok = perform_job(PlacementWorker, %{})

    # Both passes spent the same kind's single applies-per-day, so the second
    # account is still waiting even though a budget elsewhere went unused.
    applied =
      [first, second]
      |> Enum.map(&PlacerRegions.primary_region/1)
      |> Enum.count(&(&1 == "eu-west"))

    assert applied == 1
  end

  test "applies every open proposal of an uncapped kind in one pass" do
    # What bounds an uncapped kind is the policy, per account. A fleet-wide
    # count in front of a queue that grows with the account count only ever
    # falls further behind.
    stub_budgets(%{correct: :unlimited})
    accounts = for _ <- 1..4, do: account_with_moved_traffic()

    assert :ok = perform_job(PlacementWorker, %{})

    applied =
      accounts
      |> Enum.map(&PlacerRegions.primary_region/1)
      |> Enum.count(&(&1 == "eu-central"))

    assert applied == 4
  end

  test "an uncapped kind is not held back by what it already spent today" do
    # The trailing-day spend is what a ceiling is measured against, so a kind
    # without one must not accumulate against it either.
    stub_budgets(%{correct: :unlimited})
    first = for _ <- 1..3, do: account_with_moved_traffic()

    assert :ok = perform_job(PlacementWorker, %{})

    second = for _ <- 1..3, do: account_with_moved_traffic()

    assert :ok = perform_job(PlacementWorker, %{})

    applied =
      (first ++ second)
      |> Enum.map(&PlacerRegions.primary_region/1)
      |> Enum.count(&(&1 == "eu-central"))

    assert applied == 6
  end

  test "a capped kind still stops at its ceiling while another runs uncapped" do
    stub_budgets(%{correct: :unlimited, expand: 1})
    accounts = for _ <- 1..3, do: account_with_moved_traffic()

    assert :ok = perform_job(PlacementWorker, %{})

    applied =
      accounts
      |> Enum.map(&PlacerRegions.primary_region/1)
      |> Enum.count(&(&1 == "eu-central"))

    assert applied == 3
  end

  defp stub_budgets(budgets) do
    configured = Map.new(budgets, fn {kind, count} -> {to_string(kind), count} end)
    stub(Environment, :kura_placement_automatic_applies_per_day, fn -> configured end)
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
