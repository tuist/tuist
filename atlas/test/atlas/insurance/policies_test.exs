defmodule Atlas.Insurance.PoliciesTest do
  use Atlas.DataCase, async: true

  import Atlas.AssetsFixtures
  import Atlas.InsuranceFixtures

  alias Atlas.Insurance.Policies
  alias Atlas.Insurance.Policy

  describe "create/1" do
    test "creates a policy from Alte-Leipziger-shaped attrs" do
      assert {:ok, %Policy{} = policy} = Policies.create(policy_attrs())
      assert policy.provider == "Alte Leipziger"
      assert Decimal.equal?(policy.sum_insured, Decimal.new("100000.00"))
      assert policy.provisional_cover_pct == 50
      assert policy.status == "quoted"
    end

    test "computes the effective cap from sum_insured and provisional_cover_pct" do
      {:ok, policy} = Policies.create(policy_attrs())
      cap = Policy.effective_cap(policy)
      assert Decimal.equal?(cap, Decimal.new("150000.00"))
    end

    test "rejects a negative sum insured" do
      assert {:error, changeset} =
               Policies.create(policy_attrs(sum_insured: Decimal.new("-1")))

      refute changeset.valid?
    end
  end

  describe "activate/2" do
    test "activates a quoted policy and sets starts_on when provided" do
      {:ok, policy} = Policies.create(policy_attrs())

      assert {:ok, updated} = Policies.activate(policy, starts_on: ~D[2026-09-15])
      assert updated.status == "active"
      assert updated.starts_on == ~D[2026-09-15]
    end
  end

  describe "add_member/2" do
    setup do
      {:ok, policy} = Policies.create(policy_attrs())
      %{policy: policy, asset: insert_asset!()}
    end

    test "declares an asset under the policy", %{policy: policy, asset: asset} do
      assert {:ok, member} =
               Policies.add_member(policy, %{
                 asset_id: asset.id,
                 declared_value: Decimal.new("9299.00"),
                 covered_from: ~D[2026-09-10]
               })

      assert member.policy_id == policy.id
      assert member.asset_id == asset.id
      assert Decimal.equal?(member.declared_value, Decimal.new("9299.00"))
      assert member.covered_from == ~D[2026-09-10]
      assert member.covered_to == nil
    end

    test "rejects a duplicate open member on the same policy", %{policy: policy, asset: asset} do
      {:ok, _} =
        Policies.add_member(policy, %{
          asset_id: asset.id,
          declared_value: Decimal.new("100.00"),
          covered_from: ~D[2026-09-10]
        })

      assert {:error, changeset} =
               Policies.add_member(policy, %{
                 asset_id: asset.id,
                 declared_value: Decimal.new("100.00"),
                 covered_from: ~D[2026-09-11]
               })

      refute changeset.valid?
    end

    test "allows a member on a different policy for the same asset", %{policy: policy, asset: asset} do
      {:ok, other} = Policies.create(policy_attrs(product: "Rider"))

      {:ok, _} =
        Policies.add_member(policy, %{
          asset_id: asset.id,
          declared_value: Decimal.new("100.00"),
          covered_from: ~D[2026-09-10]
        })

      assert {:ok, _} =
               Policies.add_member(other, %{
                 asset_id: asset.id,
                 declared_value: Decimal.new("50.00"),
                 covered_from: ~D[2026-09-10]
               })
    end
  end

  describe "close_member/2" do
    test "closes an open member on the given date" do
      {:ok, policy} = Policies.create(policy_attrs())
      asset = insert_asset!()

      {:ok, member} =
        Policies.add_member(policy, %{
          asset_id: asset.id,
          declared_value: Decimal.new("100.00"),
          covered_from: ~D[2026-09-10]
        })

      assert {:ok, closed} = Policies.close_member(member, covered_to: ~D[2026-09-30])
      assert closed.covered_to == ~D[2026-09-30]
    end
  end

  describe "expire/2" do
    test "expires the policy and closes open members" do
      {:ok, policy} = Policies.create(policy_attrs())
      {:ok, policy} = Policies.activate(policy, starts_on: ~D[2026-09-15])
      asset = insert_asset!()

      {:ok, _} =
        Policies.add_member(policy, %{
          asset_id: asset.id,
          declared_value: Decimal.new("100.00"),
          covered_from: ~D[2026-09-15]
        })

      assert {:ok, expired} = Policies.expire(policy, ends_on: ~D[2026-12-31])
      assert expired.status == "expired"
      assert expired.ends_on == ~D[2026-12-31]
      assert Policies.list_open_members(expired) == []
    end
  end

  describe "create_claim/2" do
    test "records a claim against a policy" do
      {:ok, policy} = Policies.create(policy_attrs())

      assert {:ok, claim} =
               Policies.create_claim(policy, %{
                 incident_on: ~D[2026-10-01],
                 incident_type: "damage",
                 status: "draft",
                 claimed_amount: Decimal.new("1500.00")
               })

      assert claim.policy_id == policy.id
      assert claim.incident_type == "damage"
    end

    test "rejects an incident_type outside the enum" do
      {:ok, policy} = Policies.create(policy_attrs())

      assert {:error, changeset} =
               Policies.create_claim(policy, %{
                 incident_on: ~D[2026-10-01],
                 incident_type: "meteor"
               })

      refute changeset.valid?
    end
  end
end
