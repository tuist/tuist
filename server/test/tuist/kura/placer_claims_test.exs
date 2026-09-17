defmodule Tuist.Kura.PlacerClaimsTest do
  use TuistTestSupport.Cases.DataCase, async: true

  alias Tuist.Accounts
  alias Tuist.Kura.PlacerClaims
  alias Tuist.Kura.Server
  alias Tuist.Repo
  alias TuistTestSupport.Fixtures.AccountsFixtures
  alias TuistTestSupport.Fixtures.BillingFixtures

  setup do
    user = AccountsFixtures.user_fixture()
    account = Accounts.get_account_from_user(user)
    BillingFixtures.subscription_fixture(account_id: account.id, plan: :enterprise)

    %{account: Repo.preload(account, :subscriptions)}
  end

  defp insert_server!(account, region, claim_size, status) do
    %{
      account_id: account.id,
      region: region,
      provisioner_node_ref: "kura-#{account.name}-#{region}",
      storage_claim_size: claim_size
    }
    |> Server.create_changeset()
    |> Repo.insert!()
    |> Ecto.Changeset.change(status: status)
    |> Repo.update!()
  end

  describe "effective_claim_size/1" do
    test "falls back to the plan's claim when nothing is pinned or sized", %{account: account} do
      assert PlacerClaims.effective_claim_size(account) == "16Gi"
    end

    test "takes the sized claim ahead of the plan's", %{account: account} do
      :ok = PlacerClaims.put(account, "20Gi")

      assert PlacerClaims.effective_claim_size(account) == "20Gi"
    end

    test "takes what the account's instances are pinned at ahead of the sized claim", %{account: account} do
      :ok = PlacerClaims.put(account, "20Gi")
      insert_server!(account, "us-east", "50Gi", :active)

      assert PlacerClaims.effective_claim_size(account) == "50Gi"
    end

    test "takes the largest pin when the account's instances disagree", %{account: account} do
      insert_server!(account, "us-east", "16Gi", :active)
      insert_server!(account, "us-west", "50Gi", :drain_pending)
      insert_server!(account, "eu-west", "1Ti", :failed)
      insert_server!(account, "sa-west", "900Gi", :replicating)

      assert PlacerClaims.effective_claim_size(account) == "1Ti"
    end

    test "ignores instances that hold no volumes", %{account: account} do
      insert_server!(account, "us-east", "50Gi", :archived)
      insert_server!(account, "us-west", "50Gi", :destroyed)
      insert_server!(account, "eu-west", "50Gi", :destroying)

      assert PlacerClaims.effective_claim_size(account) == "16Gi"
    end

    test "ignores claims carried outside the storage-governed regions", %{account: account} do
      insert_server!(account, "local-controller", "50Gi", :active)

      assert PlacerClaims.effective_claim_size(account) == "16Gi"
    end
  end
end
