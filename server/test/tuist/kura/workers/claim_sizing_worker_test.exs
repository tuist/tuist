defmodule Tuist.Kura.Workers.ClaimSizingWorkerTest do
  use TuistTestSupport.Cases.DataCase, async: true

  import Mimic

  alias Tuist.Accounts
  alias Tuist.Kura.ClaimProposal
  alias Tuist.Kura.ClaimProposals
  alias Tuist.Kura.PlacerClaims
  alias Tuist.Kura.Server
  alias Tuist.Kura.StorageRollup
  alias Tuist.Kura.Workers.ClaimSizingWorker
  alias Tuist.Repo
  alias TuistTestSupport.Fixtures.AccountsFixtures
  alias TuistTestSupport.Fixtures.BillingFixtures

  setup :set_mimic_from_context

  @gibibyte 1024 * 1024 * 1024

  setup do
    stub(Tuist.Environment, :tuist_hosted?, fn -> true end)

    user = AccountsFixtures.user_fixture()
    account = Accounts.get_account_from_user(user)
    BillingFixtures.subscription_fixture(account_id: account.id, plan: :pro)

    {:ok, _server} =
      %Server{}
      |> Server.create_changeset(%{
        account_id: account.id,
        region: "us-east",
        provisioner_node_ref: "kura-#{account.name}-us-east"
      })
      |> Repo.insert()

    # The worker sweeps against the real current date, so the churn window
    # ends today.
    now = DateTime.truncate(DateTime.utc_now(), :second)

    rows =
      for offset <- 13..0//-1 do
        %{
          account_id: account.id,
          region: "us-east",
          date: Date.add(Date.utc_today(), -offset),
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

    %{account: account}
  end

  test "writes proposals but applies nothing while the automatic flag is off", %{account: account} do
    stub(Tuist.FeatureFlags, :kura_claim_sizing_automatic?, fn -> false end)

    assert :ok = perform_job(ClaimSizingWorker, %{})

    assert %ClaimProposal{status: :open} = ClaimProposals.open_proposal_for(account)
    assert PlacerClaims.claim_for(account) == nil
  end

  test "applies open proposals when the automatic flag is on", %{account: account} do
    stub(Tuist.FeatureFlags, :kura_claim_sizing_automatic?, fn -> true end)

    assert :ok = perform_job(ClaimSizingWorker, %{})

    assert PlacerClaims.claim_for(account) == "16Gi"
    assert [%ClaimProposal{status: :applied, resolved_by: "automatic"}] = Repo.all(ClaimProposal)
  end

  test "the unattended budget is spent per hour, not per pass", %{account: account} do
    stub(Tuist.FeatureFlags, :kura_claim_sizing_automatic?, fn -> true end)

    # Five automatic applies already this hour: the fleet's unattended budget
    # is gone, so a pass that would otherwise apply does nothing. This is what
    # keeps the blast radius fixed while the sweep runs every ten minutes.
    now = DateTime.truncate(DateTime.utc_now(), :second)

    for _ <- 1..5 do
      other = AccountsFixtures.organization_fixture().account

      Repo.insert!(%ClaimProposal{
        account_id: other.id,
        region: "us-east",
        direction: :grow,
        current_claim_size: "8Gi",
        recommended_claim_size: "16Gi",
        status: :applied,
        resolved_by: "automatic",
        resolved_at: DateTime.add(now, -600, :second)
      })
    end

    assert :ok = perform_job(ClaimSizingWorker, %{})

    assert PlacerClaims.claim_for(account) == nil
    assert %ClaimProposal{status: :open} = ClaimProposals.open_proposal_for(account)
  end

  test "operator applies do not consume the unattended budget", %{account: account} do
    stub(Tuist.FeatureFlags, :kura_claim_sizing_automatic?, fn -> true end)

    now = DateTime.truncate(DateTime.utc_now(), :second)

    for _ <- 1..5 do
      other = AccountsFixtures.organization_fixture().account

      Repo.insert!(%ClaimProposal{
        account_id: other.id,
        region: "us-east",
        direction: :grow,
        current_claim_size: "8Gi",
        recommended_claim_size: "16Gi",
        status: :applied,
        resolved_by: "ops@tuist.dev",
        resolved_at: DateTime.add(now, -600, :second)
      })
    end

    assert :ok = perform_job(ClaimSizingWorker, %{})

    assert PlacerClaims.claim_for(account) == "16Gi"
  end
end
