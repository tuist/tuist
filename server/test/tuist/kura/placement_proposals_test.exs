defmodule Tuist.Kura.PlacementProposalsTest do
  use TuistTestSupport.Cases.DataCase, async: true

  import Mimic

  alias Tuist.Accounts
  alias Tuist.Kura
  alias Tuist.Kura.AccountPolicies
  alias Tuist.Kura.OriginRollup
  alias Tuist.Kura.PlacementProposal
  alias Tuist.Kura.PlacementProposals
  alias Tuist.Kura.PlacerRegion
  alias Tuist.Kura.PlacerRegions
  alias Tuist.Kura.Server
  alias Tuist.Repo
  alias TuistTestSupport.Fixtures.AccountsFixtures
  alias TuistTestSupport.Fixtures.BillingFixtures

  setup :set_mimic_from_context

  @today Date.utc_today()

  setup do
    stub(Tuist.Environment, :tuist_hosted?, fn -> true end)
    stub(Tuist.Environment, :dev?, fn -> false end)
    stub(Tuist.Environment, :test?, fn -> false end)
    stub(Tuist.Environment, :kura_available_region_ids, fn -> ["us-east", "us-west", "eu-central"] end)

    :ok
  end

  describe "sweep/1" do
    test "opens a relocation when traffic has durably moved" do
      account = paid_account()
      insert_server!(account, "us-east")
      seed_runs(account, "FR", 30, 20)

      assert {:ok, %{evaluated: 1, open: 1}} = PlacementProposals.sweep(@today)

      assert %PlacementProposal{kind: :relocate, from_region: "us-east", to_region: "eu-central", status: :open} =
               PlacementProposals.open_proposal_for(account)
    end

    test "opens nothing for an account whose traffic is where it already is" do
      account = paid_account()
      insert_server!(account, "us-east")
      seed_runs(account, "US-VA", 30, 20)

      assert {:ok, %{evaluated: 1, open: 0}} = PlacementProposals.sweep(@today)
      assert PlacementProposals.open_proposal_for(account) == nil
    end

    test "leaves an account an operator pinned entirely alone" do
      # The pin is this feature's per-account rollback, so it has to mean the
      # placer stops looking rather than that its proposals stop being applied.
      account = paid_account()
      insert_server!(account, "us-east")
      seed_runs(account, "FR", 30, 20)

      {:ok, _assignment} =
        AccountPolicies.assign_service_region(account, "us-east", AccountsFixtures.user_fixture(), "Pinned")

      assert {:ok, %{evaluated: 0, open: 0}} = PlacementProposals.sweep(@today)
      assert PlacementProposals.open_proposal_for(account) == nil
    end

    test "refreshes the evidence on an unchanged recommendation rather than churning rows" do
      account = paid_account()
      insert_server!(account, "us-east")
      seed_runs(account, "FR", 30, 20)

      {:ok, _first} = PlacementProposals.sweep(@today)
      opened = PlacementProposals.open_proposal_for(account)

      {:ok, _second} = PlacementProposals.sweep(@today)
      still_open = PlacementProposals.open_proposal_for(account)

      assert still_open.id == opened.id
      assert Repo.aggregate(PlacementProposal, :count) == 1
    end

    test "supersedes an open proposal the evidence no longer supports" do
      account = paid_account()
      insert_server!(account, "us-east")
      seed_runs(account, "FR", 30, 20)

      {:ok, _first} = PlacementProposals.sweep(@today)
      opened = PlacementProposals.open_proposal_for(account)

      Repo.delete_all(OriginRollup)
      seed_runs(account, "US-VA", 30, 20)

      {:ok, _second} = PlacementProposals.sweep(@today)

      assert PlacementProposals.open_proposal_for(account) == nil
      assert Repo.get(PlacementProposal, opened.id).status == :superseded
      assert Repo.get(PlacementProposal, opened.id).resolved_by == "sweep"
    end

    test "keeps at most one open proposal per account" do
      account = paid_account()
      insert_server!(account, "us-east")
      seed_runs(account, "FR", 30, 20)

      {:ok, _first} = PlacementProposals.sweep(@today)

      Repo.delete_all(OriginRollup)
      seed_runs(account, "SG", 30, 20)

      {:ok, _second} = PlacementProposals.sweep(@today)

      assert Repo.aggregate(from(p in PlacementProposal, where: p.status == :open), :count) == 1
    end

    test "reads an account the backfill never reached from its live instances" do
      account = paid_account()
      insert_server!(account, "us-east")
      seed_runs(account, "FR", 30, 20)

      assert PlacerRegions.serving_regions(account) == []

      assert {:ok, %{open: 1}} = PlacementProposals.sweep(@today)
      assert %PlacementProposal{from_region: "us-east"} = PlacementProposals.open_proposal_for(account)
    end
  end

  describe "apply_placement_proposal/2" do
    test "relocating writes the destination as primary and marks the source retiring" do
      account = paid_account()
      insert_server!(account, "us-east")
      seed_runs(account, "FR", 30, 20)
      {:ok, _summary} = PlacementProposals.sweep(@today)

      proposal = PlacementProposals.open_proposal_for(account)

      assert {:ok, %{kind: :relocate, to_region: "eu-central"}} =
               Kura.apply_placement_proposal(proposal, "operator@tuist.dev")

      assert PlacerRegions.primary_region(account) == "eu-central"
      assert PlacerRegions.retiring_regions(account) == ["us-east"]
      assert Repo.get(PlacementProposal, proposal.id).status == :applied
      assert Repo.get(PlacementProposal, proposal.id).resolved_by == "operator@tuist.dev"
    end

    test "the destination becomes the account's service region" do
      account = paid_account()
      insert_server!(account, "us-east")
      seed_runs(account, "FR", 30, 20)
      {:ok, _summary} = PlacementProposals.sweep(@today)

      {:ok, _outcome} =
        account |> PlacementProposals.open_proposal_for() |> Kura.apply_placement_proposal("operator@tuist.dev")

      assert {:ok, %{service_region: "eu-central"}} = AccountPolicies.resolve(account)
    end

    test "a retiring region is not one the account should be running in" do
      # It still serves until its drain starts, but nothing may provision it or
      # hold its demand clock warm, or the lifecycle would rebuild what the
      # retirement is removing.
      account = paid_account()
      insert_server!(account, "us-east")
      seed_runs(account, "FR", 30, 20)
      {:ok, _summary} = PlacementProposals.sweep(@today)

      {:ok, _outcome} =
        account |> PlacementProposals.open_proposal_for() |> Kura.apply_placement_proposal("operator@tuist.dev")

      assert AccountPolicies.serving_regions(account) == ["eu-central"]
      assert account |> PlacerRegions.claimed_regions() |> Enum.sort() == ["eu-central", "us-east"]
    end

    test "expanding adds a secondary and keeps the primary" do
      account = paid_account()
      insert_server!(account, "us-east")
      seed_runs(account, "US-VA", 14, 500)
      seed_runs(account, "FR", 14, 40)
      {:ok, _summary} = PlacementProposals.sweep(@today)

      proposal = PlacementProposals.open_proposal_for(account)
      assert proposal.kind == :expand

      assert {:ok, %{kind: :expand, to_region: "eu-central"}} =
               Kura.apply_placement_proposal(proposal, "operator@tuist.dev")

      assert PlacerRegions.primary_region(account) == "us-east"
      assert account |> AccountPolicies.serving_regions() |> Enum.sort() == ["eu-central", "us-east"]
    end

    test "does not propose giving up the region it just expanded into" do
      # End to end on the flapping guard: the fortnight of traffic that opens a
      # region is less than the retirement window's worth, so without the age
      # gate the very next sweep would propose closing it again.
      account = paid_account()
      insert_server!(account, "us-east")
      seed_runs(account, "US-VA", 14, 500)
      seed_runs(account, "FR", 14, 40)
      {:ok, _summary} = PlacementProposals.sweep(@today)

      {:ok, _outcome} =
        account |> PlacementProposals.open_proposal_for() |> Kura.apply_placement_proposal("operator@tuist.dev")

      assert account |> PlacerRegions.serving_regions() |> Enum.sort() == ["eu-central", "us-east"]

      {:ok, _second} = PlacementProposals.sweep(@today)

      assert PlacementProposals.open_proposal_for(account) == nil
    end

    test "refuses a proposal whose premises have changed" do
      account = paid_account()
      insert_server!(account, "us-east")
      seed_runs(account, "FR", 30, 20)
      {:ok, _summary} = PlacementProposals.sweep(@today)

      proposal = PlacementProposals.open_proposal_for(account)

      # Somebody else moved the account first.
      {:ok, _row} = PlacerRegions.put_primary(account, "us-west")

      assert Kura.apply_placement_proposal(proposal, "operator@tuist.dev") == {:error, :stale_proposal}
      assert Repo.get(PlacementProposal, proposal.id).status == :superseded
      assert Repo.get(PlacementProposal, proposal.id).resolved_by == "stale_on_apply"
      assert PlacerRegions.primary_region(account) == "us-west"
    end

    test "refuses a proposal that is no longer open" do
      account = paid_account()
      insert_server!(account, "us-east")
      seed_runs(account, "FR", 30, 20)
      {:ok, _summary} = PlacementProposals.sweep(@today)

      proposal = PlacementProposals.open_proposal_for(account)
      {:ok, _dismissed} = PlacementProposals.dismiss(proposal, "operator@tuist.dev")

      assert Kura.apply_placement_proposal(proposal, "someone.else@tuist.dev") == {:error, :stale_proposal}
      assert PlacerRegions.primary_region(account) == nil
    end

    test "materialises the account's current placement before changing it" do
      # Without this, applying a relocation to an account the backfill never
      # reached would write the destination and leave the source with no row to
      # retire, stranding it.
      account = paid_account()
      insert_server!(account, "us-east")
      seed_runs(account, "FR", 30, 20)
      {:ok, _summary} = PlacementProposals.sweep(@today)

      assert Repo.aggregate(PlacerRegion, :count) == 0

      {:ok, _outcome} =
        account |> PlacementProposals.open_proposal_for() |> Kura.apply_placement_proposal("operator@tuist.dev")

      assert Repo.aggregate(PlacerRegion, :count) == 2
    end
  end

  describe "the automatic budget" do
    test "counts only what the sweep applied on its own" do
      account = paid_account()
      insert_server!(account, "us-east")
      seed_runs(account, "FR", 30, 20)
      {:ok, _summary} = PlacementProposals.sweep(@today)

      {:ok, _outcome} =
        account |> PlacementProposals.open_proposal_for() |> Kura.apply_placement_proposal("operator@tuist.dev")

      since = DateTime.add(DateTime.utc_now(), -3600, :second)

      assert PlacementProposals.automatic_applies_since(since) == 0
    end

    test "counts an automatic apply" do
      account = paid_account()
      insert_server!(account, "us-east")
      seed_runs(account, "FR", 30, 20)
      {:ok, _summary} = PlacementProposals.sweep(@today)

      {:ok, _outcome} =
        account |> PlacementProposals.open_proposal_for() |> Kura.apply_placement_proposal("automatic")

      since = DateTime.add(DateTime.utc_now(), -3600, :second)

      assert PlacementProposals.automatic_applies_since(since) == 1
    end
  end

  test "dismiss/2 closes an open proposal and refuses a closed one" do
    account = paid_account()
    insert_server!(account, "us-east")
    seed_runs(account, "FR", 30, 20)
    {:ok, _summary} = PlacementProposals.sweep(@today)

    proposal = PlacementProposals.open_proposal_for(account)

    assert {:ok, %PlacementProposal{status: :dismissed}} = PlacementProposals.dismiss(proposal, "operator@tuist.dev")
    assert PlacementProposals.dismiss(proposal, "operator@tuist.dev") == {:error, :not_open}
  end

  defp paid_account do
    user = AccountsFixtures.user_fixture()
    account = Accounts.get_account_from_user(user)
    BillingFixtures.subscription_fixture(account_id: account.id, plan: :pro)

    account
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

  defp seed_runs(account, origin, days, runs_per_day) do
    now = DateTime.truncate(DateTime.utc_now(), :second)

    rows =
      for offset <- 0..(days - 1) do
        %{
          account_id: account.id,
          origin: origin,
          date: Date.add(@today, -offset),
          run_count: runs_per_day,
          demand_count: 0,
          inserted_at: now,
          updated_at: now
        }
      end

    Repo.insert_all(OriginRollup, rows)
  end
end
