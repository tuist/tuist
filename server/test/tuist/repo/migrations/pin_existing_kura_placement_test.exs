Code.require_file(Path.expand("../../../../priv/repo/migrations/20260826141800_pin_existing_kura_placement.exs", __DIR__))

defmodule Tuist.Repo.Migrations.PinExistingKuraPlacementTest do
  use TuistTestSupport.Cases.DataCase, async: false

  import Ecto.Query
  import Mimic

  alias Tuist.Accounts
  alias Tuist.Kura.PlacerRegion
  alias Tuist.Kura.Server
  alias Tuist.Repo
  alias Tuist.Repo.Migrations.PinExistingKuraPlacement
  alias TuistTestSupport.Fixtures.AccountsFixtures

  setup :set_mimic_from_context

  setup do
    stub(Tuist.Environment, :tuist_hosted?, fn -> true end)
    :ok
  end

  test "records the oldest live instance as the primary and the rest as secondaries" do
    account = account()
    insert_server(account, "us-east", age_days: 60)
    insert_server(account, "eu-central", age_days: 30)

    PinExistingKuraPlacement.pin_existing_placement!(Repo)

    assert placement(account, "us-east").role == :primary
    assert placement(account, "eu-central").role == :secondary
  end

  test "records every placement as one the placer must decide its way out of" do
    account = account()
    insert_server(account, "us-east", age_days: 60)

    PinExistingKuraPlacement.pin_existing_placement!(Repo)

    assert placement(account, "us-east").status == :desired
    assert placement(account, "us-east").evidence == %{"signal" => "pinned_existing_placement"}
  end

  test "leaves out the instances that hold no region" do
    # An archived or destroyed instance owns nothing to be placed at, and a
    # runner cache is placed by runner availability rather than by traffic.
    account = account()
    insert_server(account, "us-east", age_days: 60)
    insert_server(account, "ca-east", status: :archived)
    insert_server(account, "us-west", status: :destroyed)
    insert_server(account, "scw-fr-par-runners")

    PinExistingKuraPlacement.pin_existing_placement!(Repo)

    assert placements(account) == ["us-east"]
  end

  test "leaves the transient rows of a warm handoff out of the placement" do
    account = account()
    insert_server(account, "us-east", age_days: 60)
    insert_server(account, "eu-central", move_phase: :moving_in)

    PinExistingKuraPlacement.pin_existing_placement!(Repo)

    assert placements(account) == ["us-east"]
  end

  test "is safe to run twice" do
    account = account()
    insert_server(account, "us-east", age_days: 60)

    PinExistingKuraPlacement.pin_existing_placement!(Repo)
    PinExistingKuraPlacement.pin_existing_placement!(Repo)

    assert placements(account) == ["us-east"]
  end

  test "gives every account exactly one primary" do
    first = account()
    second = account()
    insert_server(first, "us-east", age_days: 60)
    insert_server(first, "eu-central", age_days: 30)
    insert_server(second, "eu-central", age_days: 10)

    PinExistingKuraPlacement.pin_existing_placement!(Repo)

    for account <- [first, second] do
      query = where(PlacerRegion, [placer], placer.account_id == ^account.id and placer.role == :primary)

      # excellent_migrations:safety-assured-for-next-line operation_all
      assert query |> Repo.all() |> length() == 1
    end
  end

  defp account do
    user = AccountsFixtures.user_fixture()
    Accounts.get_account_from_user(user)
  end

  defp insert_server(account, region, attrs \\ []) do
    inserted_at = DateTime.add(DateTime.utc_now(), -Keyword.get(attrs, :age_days, 1) * 86_400, :second)

    server = %Server{
      account_id: account.id,
      region: region,
      status: Keyword.get(attrs, :status, :active),
      move_phase: Keyword.get(attrs, :move_phase, :none),
      provisioner_node_ref: "kura-#{account.id}-#{region}-#{System.unique_integer([:positive])}"
    }

    # excellent_migrations:safety-assured-for-next-line operation_insert
    inserted = Repo.insert!(server)

    # excellent_migrations:safety-assured-for-next-line operation_update
    Repo.update!(Ecto.Changeset.change(inserted, %{inserted_at: inserted_at}))
  end

  defp placement(account, region) do
    # excellent_migrations:safety-assured-for-next-line operation_get_by
    Repo.get_by!(PlacerRegion, account_id: account.id, region: region)
  end

  defp placements(account) do
    query =
      PlacerRegion
      |> where([placer], placer.account_id == ^account.id)
      |> select([placer], placer.region)

    # excellent_migrations:safety-assured-for-next-line operation_all
    query |> Repo.all() |> Enum.sort()
  end
end
