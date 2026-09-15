defmodule Tuist.Kura.AdmissionTest do
  use TuistTestSupport.Cases.DataCase, async: false
  use Mimic

  import Ecto.Query

  alias Tuist.Accounts
  alias Tuist.Environment
  alias Tuist.Kura
  alias Tuist.Kura.Admission
  alias Tuist.Kura.Capacity
  alias Tuist.Kura.ClaimProposal
  alias Tuist.Kura.Regions
  alias Tuist.Kura.Server
  alias Tuist.Repo
  alias TuistTestSupport.Fixtures.AccountsFixtures

  setup :set_mimic_from_context

  setup do
    stub(Environment, :kura_capacity_admission_required?, fn -> true end)
    :ok
  end

  test "counts provisioning rows that the Kubernetes API has not observed yet" do
    account = account()
    {:ok, region} = Regions.fetch("us-east")
    region_id = region.id
    pending_server(account, region.id)

    stub(Capacity, :pressure_line_gib, fn ^region_id -> 31 end)
    stub(Capacity, :reserved_gib, fn ^region_id -> 0 end)
    stub(Capacity, :resident_gib, fn ^region, _server -> 16 end)

    candidate = candidate(account, region.id)

    assert {:error, :capacity_exhausted} = Admission.admit?(region, candidate)
  end

  test "uses the larger of the observed and desired reservations" do
    account = account()
    {:ok, region} = Regions.fetch("us-east")
    region_id = region.id

    stub(Capacity, :pressure_line_gib, fn ^region_id -> 31 end)
    stub(Capacity, :reserved_gib, fn ^region_id -> 16 end)
    stub(Capacity, :resident_gib, fn ^region, _server -> 16 end)

    assert {:error, :capacity_exhausted} = Admission.admit?(region, candidate(account, region.id))
  end

  test "rejects a storage-claim increase that crosses the regional limit" do
    account = account()
    {:ok, region} = Regions.fetch("us-east")
    region_id = region.id
    current = pending_server(account, region_id)
    candidate = %{current | storage_claim_size: "16Gi"}

    stub(Capacity, :pressure_line_gib, fn ^region_id -> 31 end)
    stub(Capacity, :reserved_gib, fn ^region_id -> 16 end)

    stub(Capacity, :resident_gib, fn
      ^region, %Server{storage_claim_size: "8Gi"} -> 16
      ^region, %Server{storage_claim_size: "16Gi"} -> 32
    end)

    assert {:error, :capacity_exhausted} = Admission.admit_replacements?(region, [{current, candidate}])
  end

  # The region-wide totals cannot see that the scheduler places each replica
  # whole on one node, so admitting on them alone leaves an instance Pending
  # and its rolling rebuild deadlocked on a volume that will not release.
  test "refuses a claim increase the region has room for and no node can place" do
    account = account()
    {:ok, region} = Regions.fetch("us-east")
    region_id = region.id
    current = pending_server(account, region_id)
    candidate = %{current | storage_claim_size: "16Gi"}

    stub(Capacity, :pressure_line_gib, fn ^region_id -> 1000 end)
    stub(Capacity, :reserved_gib, fn ^region_id -> 16 end)
    stub(Capacity, :resident_gib, fn ^region, _server -> 16 end)
    stub(Capacity, :placeable?, fn ^region, %Server{storage_claim_size: "16Gi"} -> false end)

    assert {:error, :capacity_unplaceable} = Admission.admit_replacements?(region, [{current, candidate}])
  end

  test "admits a claim increase that the instance's own replicas make room for" do
    account = account()
    {:ok, region} = Regions.fetch("us-east")
    region_id = region.id
    current = pending_server(account, region_id)
    candidate = %{current | storage_claim_size: "16Gi"}

    stub(Capacity, :pressure_line_gib, fn ^region_id -> 1000 end)
    stub(Capacity, :reserved_gib, fn ^region_id -> 16 end)
    stub(Capacity, :resident_gib, fn ^region, _server -> 16 end)
    stub(Capacity, :placeable?, fn ^region, _server -> true end)

    assert :ok = Admission.admit_replacements?(region, [{current, candidate}])
  end

  # A refusal here blocks every legitimate claim growth in the region, so a
  # reading that is merely missing must never produce one.
  test "admits a claim increase while the per-node reading is unavailable" do
    account = account()
    {:ok, region} = Regions.fetch("us-east")
    region_id = region.id
    current = pending_server(account, region_id)
    candidate = %{current | storage_claim_size: "16Gi"}

    stub(Capacity, :pressure_line_gib, fn ^region_id -> 1000 end)
    stub(Capacity, :reserved_gib, fn ^region_id -> 16 end)
    stub(Capacity, :resident_gib, fn ^region, _server -> 16 end)
    stub(Capacity, :placeable?, fn ^region, _server -> nil end)

    assert :ok = Admission.admit_replacements?(region, [{current, candidate}])
  end

  test "refuses a new instance no node can place" do
    account = account()
    {:ok, region} = Regions.fetch("us-east")
    region_id = region.id

    stub(Capacity, :pressure_line_gib, fn ^region_id -> 1000 end)
    stub(Capacity, :reserved_gib, fn ^region_id -> 0 end)
    stub(Capacity, :resident_gib, fn ^region, _server -> 16 end)
    stub(Capacity, :placeable?, fn ^region, _server -> false end)

    assert {:error, :capacity_unplaceable} = Admission.admit?(region, candidate(account, region.id))
  end

  test "reports a region over its line as exhausted rather than unplaceable" do
    account = account()
    {:ok, region} = Regions.fetch("us-east")
    region_id = region.id

    stub(Capacity, :pressure_line_gib, fn ^region_id -> 31 end)
    stub(Capacity, :reserved_gib, fn ^region_id -> 16 end)
    stub(Capacity, :resident_gib, fn ^region, _server -> 16 end)
    stub(Capacity, :placeable?, fn ^region, _server -> false end)

    assert {:error, :capacity_exhausted} = Admission.admit?(region, candidate(account, region.id))
  end

  # The refusal has to reach the sweep intact: it is what the apply rolls back
  # on, and what the refusal metric is tagged with.
  test "rolls a sizing apply back, and says which refusal it was" do
    account = account()
    server = pending_server(account, "us-east")

    proposal =
      Repo.insert!(%ClaimProposal{
        account_id: account.id,
        region: "us-east",
        direction: :grow,
        current_claim_size: "8Gi",
        recommended_claim_size: "16Gi",
        status: :open
      })

    stub(Capacity, :pressure_line_gib, fn "us-east" -> 1000 end)
    stub(Capacity, :reserved_gib, fn "us-east" -> 16 end)
    stub(Capacity, :placeable?, fn _region, _server -> false end)

    assert {:error, :capacity_unplaceable} = Kura.apply_claim_proposal(proposal, "automatic")
    assert Repo.get!(Server, server.id).storage_claim_size == "8Gi"
    assert Repo.get!(ClaimProposal, proposal.id).status == :open
  end

  test "fails closed when the capacity measurement is unavailable" do
    account = account()
    {:ok, region} = Regions.fetch("us-east")
    region_id = region.id

    stub(Capacity, :pressure_line_gib, fn ^region_id -> nil end)

    assert {:error, :capacity_unknown} = Admission.admit?(region, candidate(account, region.id))
  end

  test "rejects cold provisioning before a server row is written" do
    account = account()
    configure_us_east()

    stub(Capacity, :pressure_line_gib, fn "us-east" -> 8 end)
    stub(Capacity, :reserved_gib, fn "us-east" -> 0 end)
    stub(Capacity, :resident_gib, fn _region, _server -> 16 end)

    assert {:error, :capacity_exhausted} =
             Kura.create_server(%{account_id: account.id, region: "us-east", image_tag: "0.5.2"})

    assert Repo.aggregate(from(server in Server, where: server.account_id == ^account.id), :count) == 0
  end

  test "rejects a cold return and leaves the archived server archived" do
    account = account()
    configure_us_east()
    stub(Environment, :kura_capacity_admission_required?, fn -> false end)

    {:ok, server} = Kura.create_server(%{account_id: account.id, region: "us-east", image_tag: "0.5.2"})
    archived = server |> Ecto.Changeset.change(status: :archived) |> Repo.update!()

    stub(Environment, :kura_capacity_admission_required?, fn -> true end)
    stub(Capacity, :pressure_line_gib, fn "us-east" -> 8 end)
    stub(Capacity, :reserved_gib, fn "us-east" -> 0 end)
    stub(Capacity, :resident_gib, fn _region, _server -> 16 end)

    assert {:error, :capacity_exhausted} = Kura.return_from_archive(archived, "0.5.2", account)
    assert Repo.get!(Server, server.id).status == :archived
  end

  defp configure_us_east do
    stub(Environment, :dev?, fn -> false end)
    stub(Environment, :test?, fn -> false end)
    stub(Environment, :kura_available_region_ids, fn -> ["us-east"] end)
    stub(Environment, :tuist_hosted?, fn -> true end)
  end

  defp account do
    Accounts.get_account_from_user(AccountsFixtures.user_fixture())
  end

  defp pending_server(account, region) do
    Repo.insert!(%Server{
      account_id: account.id,
      region: region,
      status: :provisioning,
      provisioner_node_ref: "kura-#{account.name}-#{region}",
      storage_claim_size: "8Gi"
    })
  end

  defp candidate(account, region) do
    %Server{
      account: account,
      account_id: account.id,
      region: region,
      status: :provisioning,
      storage_claim_size: "8Gi"
    }
  end
end
