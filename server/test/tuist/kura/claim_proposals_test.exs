defmodule Tuist.Kura.ClaimProposalsTest do
  use TuistTestSupport.Cases.DataCase, async: true

  import Ecto.Query
  import Mimic

  alias Tuist.Accounts
  alias Tuist.Kura
  alias Tuist.Kura.Capacity
  alias Tuist.Kura.ClaimProposal
  alias Tuist.Kura.ClaimProposals
  alias Tuist.Kura.PlacerClaim
  alias Tuist.Kura.PlacerClaims
  alias Tuist.Kura.Regions
  alias Tuist.Kura.Server
  alias Tuist.Kura.StorageRollup
  alias Tuist.Repo
  alias TuistTestSupport.Fixtures.AccountsFixtures
  alias TuistTestSupport.Fixtures.BillingFixtures

  setup :set_mimic_from_context

  @today ~D[2026-08-25]
  @gibibyte 1024 * 1024 * 1024

  setup do
    stub(Tuist.Environment, :tuist_hosted?, fn -> true end)

    user = AccountsFixtures.user_fixture()
    account = Accounts.get_account_from_user(user)
    BillingFixtures.subscription_fixture(account_id: account.id, plan: :pro)
    server = insert_server!(account, "us-east")

    %{account: account, server: server}
  end

  defp account_with_subscription do
    user = AccountsFixtures.user_fixture()
    account = Accounts.get_account_from_user(user)
    BillingFixtures.subscription_fixture(account_id: account.id, plan: :pro)
    insert_server!(account, "us-east")
    account
  end

  # Ecto's telemetry carries the SQL and the bound parameters, so the assertion
  # is on what the sweep actually asked the database. Telemetry handlers are
  # global to the VM rather than scoped to the test, so this counts only the
  # queries bound to this test's own accounts; without that it also sees every
  # concurrently running async test and fails on their traffic.
  defp count_subscription_queries(account_ids, fun) do
    ref = make_ref()
    test = self()
    handler = {__MODULE__, ref}

    :telemetry.attach(
      handler,
      [:tuist, :repo, :query],
      fn _event, _measurements, %{query: query, params: params}, _config ->
        if String.contains?(query, ~s(FROM "subscriptions")) and Enum.any?(params, &(&1 in account_ids)) do
          send(test, {ref, :subscription_query})
        end
      end,
      nil
    )

    try do
      fun.()
    after
      :telemetry.detach(handler)
    end

    drain_subscription_queries(ref, 0)
  end

  defp drain_subscription_queries(ref, count) do
    receive do
      {^ref, :subscription_query} -> drain_subscription_queries(ref, count + 1)
    after
      0 -> count
    end
  end

  defp insert_server!(account, region) do
    {:ok, server} =
      %Server{}
      |> Server.create_changeset(%{
        account_id: account.id,
        region: region,
        provisioner_node_ref: "kura-#{account.name}-#{region}"
      })
      |> Repo.insert()

    server
  end

  defp seed_churn_rollups(account, days, end_day, region \\ "us-east") do
    now = DateTime.truncate(DateTime.utc_now(), :second)

    rows =
      for offset <- (days - 1)..0//-1 do
        %{
          account_id: account.id,
          region: region,
          date: Date.add(end_day, -offset),
          eviction_count: 40,
          evicted_bytes: 10 * @gibibyte,
          evicted_artifact_count: 400,
          min_shed_age_seconds: 3_600,
          median_shed_age_seconds: 12 * 3_600,
          median_ring_span_seconds: div(3 * 86_400, 2),
          snapshot_count: 96,
          max_occupancy_percent: 98,
          max_live_segment_bytes: 28 * @gibibyte,
          last_ring_budget_bytes: 26 * @gibibyte,
          inserted_at: now,
          updated_at: now
        }
      end

    Repo.insert_all(StorageRollup, rows)
  end

  defp insert_applied_growth!(account, from, to, median_ring_span_seconds, resolved_at) do
    Repo.insert!(%ClaimProposal{
      account_id: account.id,
      region: "us-east",
      direction: :grow,
      current_claim_size: from,
      recommended_claim_size: to,
      evidence: %{"retention_floor_seconds" => 3 * 86_400, "median_ring_span_seconds" => median_ring_span_seconds},
      status: :applied,
      resolved_at: resolved_at,
      resolved_by: "automatic"
    })
  end

  defp pin!(server, claim_size) do
    server |> Ecto.Changeset.change(storage_claim_size: claim_size) |> Repo.update!()
  end

  # A full ring that rotates and sheds content ten days after it was written,
  # every day of the retention shrink window.
  defp seed_long_retention_rollups(account, region) do
    seed_churn_rollups(account, 30, @today, region)

    StorageRollup
    |> where([rollup], rollup.account_id == ^account.id and rollup.region == ^region)
    |> Repo.update_all(
      set: [
        eviction_count: 6,
        evicted_bytes: 4 * @gibibyte,
        median_shed_age_seconds: 10 * 86_400,
        median_ring_span_seconds: round(10.5 * 86_400)
      ]
    )
  end

  # us-east kept the 50Gi the pin migration grandfathered; eu-west was built
  # later at 16Gi. Both keep ten days, so eu-west shows the account needs far
  # less than 50Gi, while us-east's own ring still asks for 18Gi.
  defp mixed_retention_account(account, server) do
    us_east = pin!(server, "50Gi")
    eu_west = account |> insert_server!("eu-west") |> pin!("16Gi")
    seed_long_retention_rollups(account, "us-east")
    seed_long_retention_rollups(account, "eu-west")

    %{us_east: us_east, eu_west: eu_west}
  end

  defp refuse_growth_in(region_id) do
    stub(Tuist.Environment, :kura_capacity_admission_required?, fn -> true end)
    stub(Capacity, :reserved_gib, fn _region_id -> 0 end)

    stub(Capacity, :pressure_line_gib, fn
      ^region_id -> 0
      _region_id -> 10_000
    end)

    stub(Capacity, :resident_gib, fn _region, %Server{} -> 16 end)
  end

  defp pin_resized_claim!(account, server, claim_size, resized_at) do
    server |> Ecto.Changeset.change(storage_claim_size: claim_size) |> Repo.update!()

    Repo.insert!(%PlacerClaim{
      account_id: account.id,
      claim_size: claim_size,
      inserted_at: resized_at,
      updated_at: resized_at
    })
  end

  describe "sweep/2" do
    test "opens a proposal for a churning account", %{account: account} do
      seed_churn_rollups(account, 14, @today)

      assert {:ok, %{evaluated: 1, open: 1}} = ClaimProposals.sweep(@today)

      proposal = ClaimProposals.open_proposal_for(account)
      assert proposal.direction == :grow
      assert proposal.region == "us-east"
      assert proposal.current_claim_size == "8Gi"
      assert proposal.recommended_claim_size == "20Gi"
      assert proposal.evidence["signal"] == "shed_age_below_retention_floor"
    end

    test "sizes a runner-only account from its runner telemetry and preserved claim", %{
      account: account,
      server: server
    } do
      server
      |> Ecto.Changeset.change(region: "scw-fr-par-runners", storage_claim_size: "50Gi")
      |> Repo.update!()

      seed_churn_rollups(account, 14, @today, "scw-fr-par-runners")

      assert {:ok, %{evaluated: 1, open: 1}} = ClaimProposals.sweep(@today)
      proposal = ClaimProposals.open_proposal_for(account)
      assert proposal.region == "scw-fr-par-runners"
      assert proposal.current_claim_size == "50Gi"
      assert proposal.direction == :grow
      assert proposal.recommended_claim_size == "64Gi"

      assert {:ok, _result} = Kura.apply_claim_proposal(proposal, "automatic")
      assert Repo.get!(Server, server.id).storage_claim_size == "64Gi"
    end

    test "shrinks a runner claim only after the measured low-occupancy window", %{account: account, server: server} do
      server
      |> Ecto.Changeset.change(region: "scw-fr-par-runners", storage_claim_size: "50Gi")
      |> Repo.update!()

      assert {:ok, %{evaluated: 1, open: 0}} = ClaimProposals.sweep(@today)

      seed_churn_rollups(account, 30, @today, "scw-fr-par-runners")

      Repo.update_all(StorageRollup,
        set: [eviction_count: 0, max_occupancy_percent: 5, max_live_segment_bytes: 2 * @gibibyte]
      )

      assert {:ok, %{evaluated: 1, open: 1}} = ClaimProposals.sweep(@today)
      proposal = ClaimProposals.open_proposal_for(account)
      assert proposal.direction == :shrink
      assert proposal.current_claim_size == "50Gi"
      assert proposal.recommended_claim_size == "25Gi"

      assert {:ok, _result} = Kura.apply_claim_proposal(proposal, "automatic")
      assert Repo.get!(Server, server.id).storage_claim_size == "25Gi"
    end

    test "measures against what the instance is pinned at, not the plan's default", %{
      account: account,
      server: server
    } do
      # Instances keep the claim they were built at, so lowering a plan
      # constant leaves running instances above it. Baselining on the plan
      # would read this 50Gi instance as 8Gi and call a move to 16Gi a grow,
      # which on apply shrinks the volume and throws the cache away.
      server |> Ecto.Changeset.change(%{storage_claim_size: "50Gi"}) |> Repo.update!()
      seed_churn_rollups(account, 14, @today)

      {:ok, _summary} = ClaimProposals.sweep(@today)
      proposal = ClaimProposals.open_proposal_for(account)

      assert proposal.current_claim_size == "50Gi"

      assert {:ok, current} = Regions.parse_storage_quantity(proposal.current_claim_size)
      assert {:ok, recommended} = Regions.parse_storage_quantity(proposal.recommended_claim_size)

      assert recommended > current,
             "a grow proposal must not recommend less than the instance already holds"
    end

    test "raises an instance pinned below the account's claim to it, from its own ring", %{
      account: account,
      server: server
    } do
      # eu-west's 16Gi ring keeps 1.5 days: 40Gi from its own ring, under the
      # 50Gi us-east holds. Scaled from 50Gi it asked for the plan ceiling.
      us_east = pin!(server, "50Gi")
      eu_west = account |> insert_server!("eu-west") |> pin!("16Gi")
      seed_churn_rollups(account, 14, @today, "eu-west")

      assert {:ok, %{open: 1}} = ClaimProposals.sweep(@today)

      proposal = ClaimProposals.open_proposal_for(account)
      assert proposal.direction == :grow
      assert proposal.region == "eu-west"
      assert proposal.current_claim_size == "50Gi"
      assert proposal.recommended_claim_size == "50Gi"
      assert proposal.evidence["region_claim_size"] == "16Gi"

      assert {:ok, result} = Kura.apply_claim_proposal(proposal, "automatic")
      assert Enum.map(result.raised, & &1.id) == [eu_west.id]
      assert result.lowered == []
      assert Repo.get!(Server, us_east.id).storage_claim_size == "50Gi"
      assert Repo.get!(Server, eu_west.id).storage_claim_size == "50Gi"

      # Written even though the account's claim did not move, so the evidence
      # window restarts on the ring eu-west now runs.
      assert PlacerClaims.claim_for(account) == "50Gi"
      assert {:ok, %{open: 0}} = ClaimProposals.sweep(@today)
    end

    test "shrinks a grandfathered claim that keeps weeks of content", %{account: account, server: server} do
      pin!(server, "50Gi")
      seed_long_retention_rollups(account, "us-east")

      assert {:ok, %{open: 1}} = ClaimProposals.sweep(@today)

      proposal = ClaimProposals.open_proposal_for(account)
      assert proposal.direction == :shrink
      assert proposal.current_claim_size == "50Gi"
      assert proposal.recommended_claim_size == "25Gi"
      assert proposal.evidence["signal"] == "retention_above_floor"

      assert {:ok, result} = Kura.apply_claim_proposal(proposal, "automatic")
      assert result.raised == []
      assert Enum.map(result.lowered, & &1.id) == [server.id]
      assert Repo.get!(Server, server.id).storage_claim_size == "25Gi"
    end

    test "a second sweep refreshes the open proposal instead of stacking another", %{account: account} do
      seed_churn_rollups(account, 14, @today)

      {:ok, _summary} = ClaimProposals.sweep(@today)
      first = ClaimProposals.open_proposal_for(account)

      {:ok, _summary} = ClaimProposals.sweep(@today)
      second = ClaimProposals.open_proposal_for(account)

      assert second.id == first.id
      assert Repo.aggregate(ClaimProposal, :count) == 1
    end

    test "a withdrawn recommendation supersedes the open proposal", %{account: account} do
      seed_churn_rollups(account, 14, @today)
      {:ok, _summary} = ClaimProposals.sweep(@today)

      # Two days later the streak is broken: the window may end a day early,
      # but not two, and no rollups exist past @today.
      later = Date.add(@today, 2)
      assert {:ok, %{open: 0}} = ClaimProposals.sweep(later)

      assert ClaimProposals.open_proposal_for(account) == nil
      assert [%ClaimProposal{status: :superseded, resolved_by: "sweep"}] = Repo.all(ClaimProposal)
    end

    test "resolves every account's plan without a query per account" do
      # The sweep asks each account for its plan on every pass, and
      # `Billing.effective_plan/1` only answers from memory when subscriptions
      # are loaded. Left unloaded it is one query per account per tick, which
      # is the one cost in the sweep that scales with both the fleet and the
      # cadence.
      first = account_with_subscription()
      second = account_with_subscription()
      seed_churn_rollups(first, 14, @today)
      seed_churn_rollups(second, 14, @today)

      subscription_queries =
        count_subscription_queries([first.id, second.id], fn ->
          {:ok, _summary} = ClaimProposals.sweep(@today)
        end)

      assert subscription_queries <= 1,
             "expected the plan lookup to be batched, saw #{subscription_queries} subscription queries"
    end

    test "an account with instances only outside storage-governed regions is invisible" do
      stub(Tuist.Environment, :tuist_hosted?, fn -> true end)
      user = AccountsFixtures.user_fixture()
      account = Accounts.get_account_from_user(user)
      insert_server!(account, "local-controller")
      seed_churn_rollups(account, 14, @today)

      {:ok, _summary} = ClaimProposals.sweep(@today)

      assert ClaimProposals.open_proposal_for(account) == nil
    end

    test "a growth capped below its projection lets the next step confirm on one day", %{
      account: account,
      server: server
    } do
      resized_at = DateTime.new!(Date.add(@today, -1), ~T[14:00:00], "Etc/UTC")
      insert_applied_growth!(account, "8Gi", "16Gi", 20_528, resized_at)
      pin_resized_claim!(account, server, "16Gi", resized_at)
      seed_churn_rollups(account, 1, @today)

      Repo.update_all(StorageRollup,
        set: [
          evicted_bytes: 14 * @gibibyte,
          last_ring_budget_bytes: 13 * @gibibyte,
          min_ring_budget_bytes: 13 * @gibibyte
        ]
      )

      assert {:ok, %{evaluated: 1, open: 1}} = ClaimProposals.sweep(@today)

      proposal = ClaimProposals.open_proposal_for(account)
      assert proposal.current_claim_size == "16Gi"
      assert proposal.recommended_claim_size == "32Gi"
      assert proposal.evidence["window_days"] == 1
      assert proposal.evidence["after_capped_resize"] == true
    end

    test "a growth that reached its projection leaves the next step to the normal window", %{
      account: account,
      server: server
    } do
      insert_applied_growth!(account, "8Gi", "16Gi", 20_528, DateTime.new!(Date.add(@today, -3), ~T[14:00:00], "Etc/UTC"))

      resized_at = DateTime.new!(Date.add(@today, -1), ~T[14:00:00], "Etc/UTC")
      insert_applied_growth!(account, "16Gi", "20Gi", 3 * 86_400, resized_at)
      pin_resized_claim!(account, server, "20Gi", resized_at)
      seed_churn_rollups(account, 1, @today)
      Repo.update_all(StorageRollup, set: [last_ring_budget_bytes: 17 * @gibibyte, min_ring_budget_bytes: 17 * @gibibyte])

      assert {:ok, %{evaluated: 1, open: 0}} = ClaimProposals.sweep(@today)
    end
  end

  describe "dismiss/2" do
    test "closes the proposal without touching the claim", %{account: account} do
      seed_churn_rollups(account, 14, @today)
      {:ok, _summary} = ClaimProposals.sweep(@today)
      proposal = ClaimProposals.open_proposal_for(account)

      assert {:ok, dismissed} = ClaimProposals.dismiss(proposal, "ops@tuist.dev")
      assert dismissed.status == :dismissed
      assert dismissed.resolved_by == "ops@tuist.dev"
      assert PlacerClaims.claim_for(account) == nil
      assert PlacerClaims.effective_claim_size(account) == "8Gi"
    end

    test "a stale struct cannot dismiss an already applied proposal", %{account: account} do
      seed_churn_rollups(account, 14, @today)
      {:ok, _summary} = ClaimProposals.sweep(@today)
      proposal = ClaimProposals.open_proposal_for(account)

      # The LiveView holds this struct while automatic sizing applies the
      # proposal underneath it; the later Dismiss click must lose the race
      # rather than overwrite the applied resolution.
      assert {:ok, _result} = Kura.apply_claim_proposal(proposal, "automatic")

      assert ClaimProposals.dismiss(proposal, "ops@tuist.dev") == {:error, :not_open}

      resolved = Repo.get!(ClaimProposal, proposal.id)
      assert resolved.status == :applied
      assert resolved.resolved_by == "automatic"
    end

    test "dismissing a resolved proposal is refused", %{account: account} do
      seed_churn_rollups(account, 14, @today)
      {:ok, _summary} = ClaimProposals.sweep(@today)
      proposal = ClaimProposals.open_proposal_for(account)
      {:ok, dismissed} = ClaimProposals.dismiss(proposal, "ops@tuist.dev")

      assert ClaimProposals.dismiss(dismissed, "ops@tuist.dev") == {:error, :not_open}
    end
  end

  describe "Kura.apply_claim_proposal/2" do
    test "names the region that refused, which need not be the one that proposed", %{account: account} do
      # A claim is account-wide, so applying it grows every governed instance the
      # account runs. The proposal names the region whose demand sized it; the
      # refusal can come from any other.
      insert_server!(account, "eu-west")
      seed_churn_rollups(account, 14, @today)
      {:ok, _summary} = ClaimProposals.sweep(@today)
      proposal = ClaimProposals.open_proposal_for(account)
      assert proposal.region == "us-east"

      stub(Tuist.Environment, :kura_capacity_admission_required?, fn -> true end)
      stub(Capacity, :reserved_gib, fn _region_id -> 0 end)

      stub(Capacity, :pressure_line_gib, fn
        "eu-west" -> 0
        _region_id -> 10_000
      end)

      stub(Capacity, :resident_gib, fn
        _region, %Server{storage_claim_size: "20Gi"} -> 40
        _region, %Server{} -> 16
      end)

      assert {:error, {"eu-west", :capacity_exhausted}} = Kura.apply_claim_proposal(proposal, "automatic")
      assert Repo.get!(ClaimProposal, proposal.id).status == :open
    end

    test "writes the sized claim, re-pins the instance, and resolves the proposal", %{
      account: account,
      server: server
    } do
      seed_churn_rollups(account, 14, @today)
      {:ok, _summary} = ClaimProposals.sweep(@today)
      proposal = ClaimProposals.open_proposal_for(account)

      assert {:ok, result} = Kura.apply_claim_proposal(proposal, "ops@tuist.dev")

      assert result.claim_size == "20Gi"
      assert [raised_server] = result.raised
      assert raised_server.id == server.id
      assert Repo.get!(Server, server.id).storage_claim_size == "20Gi"
      assert PlacerClaims.claim_for(account) == "20Gi"
      assert PlacerClaims.effective_claim_size(account) == "20Gi"

      resolved = Repo.get!(ClaimProposal, proposal.id)
      assert resolved.status == :applied
      assert resolved.resolved_by == "ops@tuist.dev"

      # The next sweep proposes nothing even though the churn rollups are
      # still present: days at or before the resize measured the old ring
      # and cannot qualify a window.
      assert {:ok, %{open: 0}} = ClaimProposals.sweep(@today)
    end

    test "moves every instance to the one claim, raising some and lowering others", %{
      account: account,
      server: server
    } do
      %{us_east: us_east, eu_west: eu_west} = mixed_retention_account(account, server)
      {:ok, %{open: 1}} = ClaimProposals.sweep(@today)
      proposal = ClaimProposals.open_proposal_for(account)

      assert proposal.direction == :shrink
      assert proposal.current_claim_size == "50Gi"
      assert proposal.recommended_claim_size == "18Gi"

      assert {:ok, result} = Kura.apply_claim_proposal(proposal, "automatic")

      assert result.claim_size == "18Gi"
      assert Enum.map(result.raised, & &1.id) == [eu_west.id]
      assert Enum.map(result.lowered, & &1.id) == [us_east.id]
      assert Repo.get!(Server, us_east.id).storage_claim_size == "18Gi"
      assert Repo.get!(Server, eu_west.id).storage_claim_size == "18Gi"
      assert PlacerClaims.claim_for(account) == "18Gi"
      assert PlacerClaims.effective_claim_size(account) == "18Gi"
    end

    test "a region refusing the raise leaves every instance and the claim as they were", %{
      account: account,
      server: server
    } do
      %{us_east: us_east, eu_west: eu_west} = mixed_retention_account(account, server)
      {:ok, %{open: 1}} = ClaimProposals.sweep(@today)
      proposal = ClaimProposals.open_proposal_for(account)
      refuse_growth_in("eu-west")

      assert {:error, {"eu-west", :capacity_exhausted}} = Kura.apply_claim_proposal(proposal, "automatic")

      assert Repo.get!(Server, us_east.id).storage_claim_size == "50Gi"
      assert Repo.get!(Server, eu_west.id).storage_claim_size == "16Gi"
      assert PlacerClaims.claim_for(account) == nil
      assert Repo.get!(ClaimProposal, proposal.id).status == :open
    end

    test "a claim that moved since the proposal supersedes instead of applying", %{account: account} do
      seed_churn_rollups(account, 14, @today)
      {:ok, _summary} = ClaimProposals.sweep(@today)
      proposal = ClaimProposals.open_proposal_for(account)

      assert :ok = PlacerClaims.put(account, "24Gi")

      assert {:error, :stale_proposal} = Kura.apply_claim_proposal(proposal, "ops@tuist.dev")
      assert Repo.get!(ClaimProposal, proposal.id).status == :superseded
      assert PlacerClaims.claim_for(account) == "24Gi"
    end

    test "an already resolved proposal does not apply twice", %{account: account} do
      seed_churn_rollups(account, 14, @today)
      {:ok, _summary} = ClaimProposals.sweep(@today)
      proposal = ClaimProposals.open_proposal_for(account)

      assert {:ok, _result} = Kura.apply_claim_proposal(proposal, "ops@tuist.dev")
      assert {:error, :stale_proposal} = Kura.apply_claim_proposal(proposal, "automatic")

      assert Repo.get!(ClaimProposal, proposal.id).resolved_by == "ops@tuist.dev"
    end
  end
end
