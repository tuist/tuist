defmodule Tuist.Kura.EgressLimitsTest do
  use TuistTestSupport.Cases.DataCase, async: true

  import Mimic

  alias Tuist.Accounts
  alias Tuist.Kura
  alias Tuist.Kura.Capacity
  alias Tuist.Kura.EgressLimits
  alias Tuist.Kura.Regions
  alias TuistTestSupport.Fixtures.AccountsFixtures
  alias TuistTestSupport.Fixtures.BillingFixtures

  setup :set_mimic_from_context

  setup do
    stub(Tuist.Environment, :tuist_hosted?, fn -> true end)
    # The node budget is a live cluster read. Every box in the fleet advertises
    # one, so the default here is a box roomier than any number these tests set;
    # the tests that care about the bound say what it is.
    stub(Capacity, :egress_budget_mbps, fn _region_id -> 3000 end)
    stub(Tuist.Environment, :dev?, fn -> false end)
    stub(Tuist.Environment, :test?, fn -> false end)
    stub(Tuist.Environment, :kura_available_region_ids, fn -> ["us-east", "eu-central"] end)

    user = AccountsFixtures.user_fixture()
    account = Accounts.get_account_from_user(user)
    # A region's floor is Enterprise-only, so that is the plan an account has to
    # be on for the region half of the pair to be anything but zero. The
    # entitlement's own behaviour has its own describe block below.
    BillingFixtures.subscription_fixture(account_id: account.id, plan: :enterprise)

    %{account: account, region: Regions.get("eu-central")}
  end

  describe "effective_limits/2" do
    test "falls back to the region's pair", %{account: account, region: region} do
      assert EgressLimits.override_for(account, region) == nil
      assert EgressLimits.effective_limits(account, region) == %{floor_mbps: 25, burst_mbps: 500}
    end

    test "takes the override ahead of the region in both directions", %{account: account, region: region} do
      # A tenant whose restores are what the rest of the box is contending with.
      assert :ok = EgressLimits.put_override(account, region, %{floor_mbps: nil, burst_mbps: 100})
      assert EgressLimits.effective_limits(account, region) == %{floor_mbps: 25, burst_mbps: 100}

      # And the other end: the region's ceiling is not a cap on what an operator
      # may hand a tenant that needs the box.
      assert :ok = EgressLimits.put_override(account, region, %{floor_mbps: 200, burst_mbps: 900})
      assert EgressLimits.effective_limits(account, region) == %{floor_mbps: 200, burst_mbps: 900}
    end

    test "resolves each half on its own", %{account: account, region: region} do
      assert :ok = EgressLimits.put_override(account, region, %{floor_mbps: 200, burst_mbps: nil})

      assert EgressLimits.effective_limits(account, region) == %{floor_mbps: 200, burst_mbps: 500}
    end

    test "a region that shapes no egress keeps both halves nil", %{account: account} do
      hetzner = %Regions{id: "cloud", display_name: "Cloud", provisioner_config: %{}}

      assert EgressLimits.default_limits(account, hetzner) == %{floor_mbps: nil, burst_mbps: nil}
      assert EgressLimits.effective_limits(account, hetzner) == %{floor_mbps: nil, burst_mbps: nil}
    end

    # The provisioner has already resolved the account's entitlements for the
    # rest of the manifest, so it hands the region floor in rather than paying
    # for a second subscription lookup here. Same resolution either way.
    test "takes an already-resolved region floor", %{account: account, region: region} do
      assert EgressLimits.effective_limits(account, region, 0) == %{floor_mbps: 0, burst_mbps: 500}

      assert :ok = EgressLimits.put_override(account, region, %{floor_mbps: 300, burst_mbps: nil})
      assert EgressLimits.effective_limits(account, region, 0) == %{floor_mbps: 300, burst_mbps: 500}
    end
  end

  describe "the plan decides the region's floor, the override outranks it" do
    setup do
      user = AccountsFixtures.user_fixture()
      %{air: Accounts.get_account_from_user(user)}
    end

    # Reserving a slice of the box is the Enterprise half of the deal; everyone
    # else bursts under the ceiling and packs densely. The form has to say so,
    # or it would promise an Air account 25 Mbps of an instance that reserves
    # nothing.
    test "an unentitled account reserves nothing by default", %{air: air, region: region} do
      assert EgressLimits.default_limits(air, region) == %{floor_mbps: 0, burst_mbps: 500}
      assert EgressLimits.effective_limits(air, region) == %{floor_mbps: 0, burst_mbps: 500}
    end

    # The gate decides the region's own floor for an account nobody has looked
    # at. An override is somebody having looked, so it wins outright.
    test "an override gives an unentitled account a floor anyway", %{air: air, region: region} do
      assert :ok = EgressLimits.put_override(air, region, %{floor_mbps: 300, burst_mbps: nil})

      assert %{floor_mbps: 300} = EgressLimits.effective_limits(air, region)
    end
  end

  describe "put_override/2" do
    test "clearing both halves removes the override", %{account: account, region: region} do
      assert :ok = EgressLimits.put_override(account, region, %{floor_mbps: 200, burst_mbps: 900})
      assert :ok = EgressLimits.put_override(account, region, %{floor_mbps: nil, burst_mbps: nil})

      assert EgressLimits.override_for(account, region) == nil
      assert EgressLimits.effective_limits(account, region) == %{floor_mbps: 25, burst_mbps: 500}
    end

    test "a second write replaces the first rather than colliding", %{account: account} = ctx do
      region = ctx[:region] || Regions.get("eu-central")
      assert :ok = EgressLimits.put_override(account, region, %{floor_mbps: 200, burst_mbps: 900})
      assert :ok = EgressLimits.put_override(account, region, %{floor_mbps: 300, burst_mbps: 800})

      assert EgressLimits.override_for(account, region) == %{floor_mbps: 300, burst_mbps: 800}
    end
  end

  describe "a region's pair is a default, not a bound" do
    setup %{account: account} do
      {:ok, _} = Kura.create_server(%{account_id: account.id, region: "us-east", image_tag: "0.5.2"})
      %{us_east: Regions.get("us-east")}
    end

    # The number the operator typed is the one they meant. A region ceiling of
    # 1500 is what an account nobody has looked at gets; it is not a statement
    # that 2000 is too much for the hardware. Only the box says that.
    test "a stated floor pulls a defaulted ceiling up to meet it", %{account: account, us_east: us_east} do
      assert {:ok, _} = EgressLimits.cast_override(account, us_east, %{"kura_egress_floor_mbps" => "2000"})
      assert :ok = EgressLimits.put_override(account, us_east, %{floor_mbps: 2000, burst_mbps: nil})

      assert EgressLimits.effective_limits(account, us_east) == %{floor_mbps: 2000, burst_mbps: 2000}
    end

    # And the other way round, for the same reason.
    test "a stated ceiling pulls a defaulted floor down to meet it", %{account: account, us_east: us_east} do
      assert :ok = EgressLimits.put_override(account, us_east, %{floor_mbps: nil, burst_mbps: 10})

      assert EgressLimits.effective_limits(account, us_east) == %{floor_mbps: 10, burst_mbps: 10}
    end

    # Both halves stated is the operator's own pair to keep coherent, and an
    # inverted one is rejected rather than silently resolved for them.
    test "still rejects a pair the operator inverted themselves", %{account: account, us_east: us_east} do
      assert {:error, changeset} =
               EgressLimits.cast_override(account, us_east, %{
                 "kura_egress_floor_mbps" => "900",
                 "kura_egress_burst_mbps" => "100"
               })

      assert ["must not exceed the ceiling"] = errors_on(changeset).kura_egress_floor_mbps
    end

    # The whole point of scoping the row to a region: the boxes differ, so an
    # override written for one says nothing about another.
    test "an override in one region leaves the others on their own defaults", %{
      account: account,
      us_east: us_east,
      region: eu_central
    } do
      {:ok, _} = Kura.create_server(%{account_id: account.id, region: "eu-central", image_tag: "0.5.2"})
      assert :ok = EgressLimits.put_override(account, us_east, %{floor_mbps: 800, burst_mbps: nil})

      assert EgressLimits.effective_limits(account, us_east) == %{floor_mbps: 800, burst_mbps: 1500}
      assert EgressLimits.effective_limits(account, eu_central) == %{floor_mbps: 25, burst_mbps: 500}
      assert EgressLimits.override_for(account, eu_central) == nil
    end

    # Each region carries its own number, which is what an account spanning
    # boxes of different sizes actually needs.
    test "each region carries its own pair", %{account: account, us_east: us_east, region: eu_central} do
      {:ok, _} = Kura.create_server(%{account_id: account.id, region: "eu-central", image_tag: "0.5.2"})
      assert :ok = EgressLimits.put_override(account, us_east, %{floor_mbps: 800, burst_mbps: 1200})
      assert :ok = EgressLimits.put_override(account, eu_central, %{floor_mbps: 100, burst_mbps: 300})

      assert EgressLimits.effective_limits(account, us_east) == %{floor_mbps: 800, burst_mbps: 1200}
      assert EgressLimits.effective_limits(account, eu_central) == %{floor_mbps: 100, burst_mbps: 300}
    end
  end

  describe "the node budget is the only bound" do
    test "rejects a floor above what the region's boxes advertise", %{account: account, region: region} do
      stub(Capacity, :egress_budget_mbps, fn "eu-central" -> 1000 end)

      assert {:error, changeset} =
               EgressLimits.cast_override(account, region, %{"kura_egress_floor_mbps" => "2000"})

      assert ["must not exceed the 1000 Mbps this region's boxes advertise"] =
               errors_on(changeset).kura_egress_floor_mbps
    end

    test "rejects a ceiling above what the region's boxes advertise", %{account: account, region: region} do
      stub(Capacity, :egress_budget_mbps, fn "eu-central" -> 1000 end)

      assert {:error, changeset} =
               EgressLimits.cast_override(account, region, %{"kura_egress_burst_mbps" => "4000"})

      assert ["must not exceed the 1000 Mbps this region's boxes advertise"] =
               errors_on(changeset).kura_egress_burst_mbps
    end

    # The region's own ceiling is 500 here, so a 900 that the box can carry is
    # accepted: the region defaults, the box bounds.
    test "accepts a value above the region's default but inside the box", %{account: account, region: region} do
      stub(Capacity, :egress_budget_mbps, fn "eu-central" -> 1000 end)

      assert {:ok, %{burst_mbps: 900}} =
               EgressLimits.cast_override(account, region, %{"kura_egress_burst_mbps" => "900"})
    end

    # A floor is the pod's request, so a budget nobody can read is a budget the
    # floor cannot be scheduled against. Refusing the edit costs a retry; taking
    # it can strand the account's cache behind a Pending pod that can never be
    # placed, because its volume pins it to the one box.
    test "refuses a floor when the budget cannot be read", %{account: account, region: region} do
      stub(Capacity, :egress_budget_mbps, fn _region_id -> nil end)

      assert {:error, changeset} =
               EgressLimits.cast_override(account, region, %{"kura_egress_floor_mbps" => "300"})

      assert ["cannot be reserved: this region's boxes advertise no egress budget to schedule it against"] =
               errors_on(changeset).kura_egress_floor_mbps
    end

    # The ceiling reserves nothing — it is an annotation the shaper reads — so
    # an unreadable budget is no reason to refuse one.
    test "still takes a ceiling when the budget cannot be read", %{account: account, region: region} do
      stub(Capacity, :egress_budget_mbps, fn _region_id -> nil end)

      assert {:ok, %{burst_mbps: 9000}} =
               EgressLimits.cast_override(account, region, %{"kura_egress_burst_mbps" => "9000"})
    end
  end

  describe "cast_override/2" do
    test "a blank field hands that number back to the region", %{account: account} = ctx do
      region = ctx[:region] || Regions.get("eu-central")

      assert {:ok, %{floor_mbps: nil, burst_mbps: 400}} =
               EgressLimits.cast_override(account, region, %{
                 "kura_egress_floor_mbps" => "",
                 "kura_egress_burst_mbps" => "400"
               })
    end

    test "rejects a floor above its ceiling", %{account: account} = ctx do
      region = ctx[:region] || Regions.get("eu-central")

      assert {:error, changeset} =
               EgressLimits.cast_override(account, region, %{
                 "kura_egress_floor_mbps" => "900",
                 "kura_egress_burst_mbps" => "100"
               })

      assert "must not exceed the ceiling" in errors_on(changeset).kura_egress_floor_mbps
    end

    test "rejects a rate no class can be built from", %{account: account} = ctx do
      region = ctx[:region] || Regions.get("eu-central")

      assert {:error, changeset} =
               EgressLimits.cast_override(account, region, %{"kura_egress_burst_mbps" => "0"})

      assert changeset.errors[:kura_egress_burst_mbps]

      assert {:error, changeset} =
               EgressLimits.cast_override(account, region, %{"kura_egress_burst_mbps" => "1000000"})

      assert changeset.errors[:kura_egress_burst_mbps]
    end

    test "seeds the form from the account's current override", %{account: account} = ctx do
      region = ctx[:region] || Regions.get("eu-central")
      assert :ok = EgressLimits.put_override(account, region, %{floor_mbps: 200, burst_mbps: 900})

      changeset = EgressLimits.change_override(account, region)

      assert Ecto.Changeset.get_field(changeset, :kura_egress_floor_mbps) == 200
      assert Ecto.Changeset.get_field(changeset, :kura_egress_burst_mbps) == 900
    end
  end
end
