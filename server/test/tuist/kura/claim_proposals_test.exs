defmodule Tuist.Kura.ClaimProposalsTest do
  use TuistTestSupport.Cases.DataCase, async: true

  import Mimic

  alias Tuist.Accounts
  alias Tuist.Kura
  alias Tuist.Kura.ClaimProposal
  alias Tuist.Kura.ClaimProposals
  alias Tuist.Kura.PlacerClaims
  alias Tuist.Kura.Server
  alias Tuist.Kura.StorageClaims
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

  defp seed_churn_rollups(account, days, end_day) do
    now = DateTime.truncate(DateTime.utc_now(), :second)

    rows =
      for offset <- (days - 1)..0//-1 do
        %{
          account_id: account.id,
          region: "us-east",
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

  describe "sweep/2" do
    test "opens a proposal for a churning account", %{account: account} do
      seed_churn_rollups(account, 14, @today)

      assert {:ok, %{evaluated: 1, open: 1}} = ClaimProposals.sweep(@today)

      proposal = ClaimProposals.open_proposal_for(account)
      assert proposal.direction == :grow
      assert proposal.region == "us-east"
      assert proposal.current_claim_size == "30Gi"
      assert proposal.recommended_claim_size == "50Gi"
      assert proposal.evidence["signal"] == "shed_age_below_retention_floor"
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

    test "an account with an operator override is invisible", %{account: account} do
      seed_churn_rollups(account, 14, @today)
      assert :ok = StorageClaims.put_override(account, "40Gi")

      assert {:ok, %{evaluated: 0, open: 0}} = ClaimProposals.sweep(@today)
      assert ClaimProposals.open_proposal_for(account) == nil
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
      assert StorageClaims.effective_claim_size(account) == "30Gi"
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
    test "writes the sized claim, re-pins the instance, and resolves the proposal", %{
      account: account,
      server: server
    } do
      seed_churn_rollups(account, 14, @today)
      {:ok, _summary} = ClaimProposals.sweep(@today)
      proposal = ClaimProposals.open_proposal_for(account)

      assert {:ok, result} = Kura.apply_claim_proposal(proposal, "ops@tuist.dev")

      assert result.claim_size == "50Gi"
      assert [raised_server] = result.raised
      assert raised_server.id == server.id
      assert Repo.get!(Server, server.id).storage_claim_size == "50Gi"
      assert PlacerClaims.claim_for(account) == "50Gi"
      assert StorageClaims.effective_claim_size(account) == "50Gi"

      resolved = Repo.get!(ClaimProposal, proposal.id)
      assert resolved.status == :applied
      assert resolved.resolved_by == "ops@tuist.dev"

      # The next sweep proposes nothing even though the churn rollups are
      # still present: days at or before the resize measured the old ring
      # and cannot qualify a window.
      assert {:ok, %{open: 0}} = ClaimProposals.sweep(@today)
    end

    test "an operator override that appeared since supersedes instead of applying", %{account: account} do
      seed_churn_rollups(account, 14, @today)
      {:ok, _summary} = ClaimProposals.sweep(@today)
      proposal = ClaimProposals.open_proposal_for(account)

      assert :ok = StorageClaims.put_override(account, "45Gi")

      assert {:error, :stale_proposal} = Kura.apply_claim_proposal(proposal, "ops@tuist.dev")
      assert Repo.get!(ClaimProposal, proposal.id).status == :superseded
      assert PlacerClaims.claim_for(account) == nil
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
