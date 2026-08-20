defmodule Tuist.Kura.StorageClaimsTest do
  use TuistTestSupport.Cases.DataCase, async: true

  import Mimic

  alias Tuist.Accounts
  alias Tuist.Kura.StorageClaims
  alias TuistTestSupport.Fixtures.AccountsFixtures
  alias TuistTestSupport.Fixtures.BillingFixtures

  setup :set_mimic_from_context

  setup do
    stub(Tuist.Environment, :tuist_hosted?, fn -> true end)

    user = AccountsFixtures.user_fixture()
    %{account: Accounts.get_account_from_user(user)}
  end

  describe "effective_claim_size/1" do
    test "falls back to the claim the account's plan buys", %{account: account} do
      assert StorageClaims.override_for(account) == nil
      assert StorageClaims.effective_claim_size(account) == "14Gi"

      BillingFixtures.subscription_fixture(account_id: account.id, plan: :enterprise)

      assert StorageClaims.effective_claim_size(account) == "50Gi"
    end

    test "takes the override ahead of the plan in both directions", %{account: account} do
      BillingFixtures.subscription_fixture(account_id: account.id, plan: :enterprise)

      # An account on the largest plan that never fills the ring it buys.
      assert :ok = StorageClaims.put_override(account, "14Gi")
      assert StorageClaims.effective_claim_size(account) == "14Gi"

      # And the other end: the plan is not a ceiling either.
      assert :ok = StorageClaims.put_override(account, "80Gi")
      assert StorageClaims.effective_claim_size(account) == "80Gi"
    end

    test "returns to the plan's claim once the override is removed", %{account: account} do
      assert :ok = StorageClaims.put_override(account, "40Gi")
      assert :ok = StorageClaims.put_override(account, nil)

      assert StorageClaims.override_for(account) == nil
      assert StorageClaims.effective_claim_size(account) == "14Gi"
    end
  end

  describe "cast_override/2" do
    test "reads a claim off the form and a blank field as removal", %{account: account} do
      assert {:ok, "24Gi"} = StorageClaims.cast_override(account, %{"kura_storage_claim_size" => "24Gi"})
      assert {:ok, nil} = StorageClaims.cast_override(account, %{"kura_storage_claim_size" => ""})
    end

    # The floor is fixed overhead, not cache need: Kura carves a flat staging
    # ceiling and a rotation segment out of any claim before it sizes the ring,
    # so a claim under it derives no ring budget at all and the runtime sizes
    # one from the whole box instead.
    test "refuses a claim under the floor every plan clears", %{account: account} do
      assert {:error, changeset} = StorageClaims.cast_override(account, %{"kura_storage_claim_size" => "11Gi"})
      assert "must be at least 14Gi" in errors_on(changeset).kura_storage_claim_size

      assert {:error, changeset} = StorageClaims.cast_override(account, %{"kura_storage_claim_size" => "500Mi"})
      assert "must be at least 14Gi" in errors_on(changeset).kura_storage_claim_size

      assert {:ok, "14Gi"} = StorageClaims.cast_override(account, %{"kura_storage_claim_size" => "14Gi"})
      assert {:ok, "1Ti"} = StorageClaims.cast_override(account, %{"kura_storage_claim_size" => "1Ti"})
    end

    test "refuses anything that is not a storage quantity", %{account: account} do
      for value <- ["big", "24GB", "-4Gi", "0Gi"] do
        assert {:error, changeset} = StorageClaims.cast_override(account, %{"kura_storage_claim_size" => value})

        assert "must be a Kubernetes storage quantity like 24Gi" in errors_on(changeset).kura_storage_claim_size
      end
    end
  end

  describe "put_override/2" do
    test "replaces the account's existing override rather than adding one", %{account: account} do
      assert :ok = StorageClaims.put_override(account, "24Gi")
      assert :ok = StorageClaims.put_override(account, "36Gi")

      assert StorageClaims.override_for(account) == "36Gi"
    end
  end
end
