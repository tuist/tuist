defmodule Tuist.Kura.Workers.ClaimSizingWorkerTest do
  use TuistTestSupport.Cases.DataCase, async: true

  import Mimic

  alias Tuist.Accounts
  alias Tuist.IngestRepo
  alias Tuist.Kura.ClaimProposal
  alias Tuist.Kura.ClaimProposals
  alias Tuist.Kura.EvictionEvent
  alias Tuist.Kura.PlacerClaims
  alias Tuist.Kura.Server
  alias Tuist.Kura.StorageRollup
  alias Tuist.Kura.StorageRollups
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

  test "rolls up a batch a node delivered days after the evictions happened", %{account: account} do
    # A node holds undelivered evictions until the control plane answers, so a
    # recovered batch arrives stamped with the day it happened. Choosing days
    # to roll up by event time would leave this one permanently unrolled, and
    # so unable to argue for a resize.
    happened = Date.add(Date.utc_today(), -9)

    IngestRepo.insert_all(EvictionEvent, [
      %{
        event_id: "late-#{account.id}",
        account_id: account.id,
        node_id: "kura-0",
        region: "us-east",
        segment_id: "segment-late-#{account.id}",
        reason: "capacity",
        evicted_at: NaiveDateTime.new!(happened, ~T[10:00:00]),
        segment_created_at: NaiveDateTime.new!(happened, ~T[08:00:00]),
        newest_content_at: NaiveDateTime.new!(happened, ~T[09:00:00]),
        artifact_count: 5,
        bytes: 536_870_912,
        inserted_at: NaiveDateTime.truncate(NaiveDateTime.utc_now(), :second)
      }
    ])

    assert :ok = perform_job(ClaimSizingWorker, %{})

    rollup = account |> StorageRollups.for_account(happened) |> Enum.find(&(&1.date == happened))

    # The seeded row said 40; only a refresh that reached this day rewrites it
    # from what the node actually reported.
    assert rollup.eviction_count == 1
    assert rollup.evicted_bytes == 536_870_912
  end

  test "applies open proposals", %{account: account} do
    assert :ok = perform_job(ClaimSizingWorker, %{})

    assert PlacerClaims.claim_for(account) == "16Gi"
    assert [%ClaimProposal{status: :applied, resolved_by: "automatic"}] = Repo.all(ClaimProposal)
  end

  test "the unattended budget is spent per hour, not per pass", %{account: account} do
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
