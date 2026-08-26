defmodule Tuist.Kura.PlacementTest do
  use ExUnit.Case, async: true

  alias Tuist.Kura.Placement

  @today ~D[2026-08-26]
  @permitted ["us-east", "us-west", "eu-central", "ap-southeast"]

  describe "relocate" do
    test "moves the primary once another region has durably carried the majority" do
      context =
        context(
          primary: "us-east",
          serving: ["us-east"],
          rollups: daily("FR", 30, 20) ++ daily("US-VA", 30, 5)
        )

      assert {:relocate, "us-east", "eu-central", evidence} = Placement.evaluate(context)
      assert evidence["signal"] == "majority_of_runs_moved"
      assert evidence["share"] >= 0.6
      assert evidence["active_days"] == 30
    end

    test "leaves an account alone below the majority" do
      context =
        context(
          primary: "us-east",
          serving: ["us-east"],
          rollups: daily("FR", 30, 12) ++ daily("US-VA", 30, 12)
        )

      assert Placement.evaluate(context) == :none
    end

    test "leaves a quiet account alone however lopsided its traffic is" do
      # The volume floor is what stops noise moving anyone: a handful of runs
      # is not evidence about where a team works.
      context =
        context(
          primary: "us-east",
          serving: ["us-east"],
          rollups: daily("FR", 30, 1)
        )

      assert Placement.evaluate(context) == :none
    end

    test "does not move on a single burst of the same volume" do
      # Durability is the point. One afternoon that clears the window's total
      # says an unusual day happened, not that the team moved.
      context =
        context(
          primary: "us-east",
          serving: ["us-east"],
          rollups: [rollup("FR", @today, 600)]
        )

      assert Placement.evaluate(context) == :none
    end

    test "does not move outside what the account is permitted" do
      # Residency is a boundary the placer never crosses: traffic from Paris
      # cannot move an account restricted to the United States to Europe.
      context =
        context(
          primary: "us-east",
          serving: ["us-east"],
          permitted: ["us-east", "us-west"],
          rollups: daily("FR", 30, 20)
        )

      assert Placement.evaluate(context) == :none
    end

    test "maps traffic to the nearest permitted region rather than refusing it" do
      # A United States account whose team works from Paris is still better
      # served from the region nearest Paris that it may use.
      context =
        context(
          primary: "us-west",
          serving: ["us-west"],
          permitted: ["us-east", "us-west"],
          rollups: daily("FR", 30, 20)
        )

      assert {:relocate, "us-west", "us-east", _evidence} = Placement.evaluate(context)
    end

    test "keeps a source region that still earns its own place" do
      # A majority moving says which region should be primary; it says nothing
      # about whether the other is still worth serving. Retiring a 35% region
      # that clears the expansion floor would drain a cache the very next sweep
      # proposes reopening.
      context =
        context(
          plan: :pro,
          primary: "us-east",
          serving: ["us-east"],
          rollups: daily("FR", 30, 65) ++ daily("US-VA", 30, 35)
        )

      assert {:relocate, "us-east", "eu-central", evidence} = Placement.evaluate(context)
      assert evidence["retire_source"] == false
    end

    test "gives up a source region whose own traffic no longer earns it" do
      context =
        context(
          plan: :pro,
          primary: "us-east",
          serving: ["us-east"],
          rollups: daily("FR", 30, 95) ++ daily("US-VA", 30, 2)
        )

      assert {:relocate, "us-east", "eu-central", evidence} = Placement.evaluate(context)
      assert evidence["retire_source"] == true
    end

    test "always gives up the source on a plan that holds one region" do
      context =
        context(
          plan: :air,
          primary: "us-east",
          serving: ["us-east"],
          rollups: daily("FR", 30, 65) ++ daily("US-VA", 30, 35)
        )

      assert {:relocate, "us-east", "eu-central", evidence} = Placement.evaluate(context)
      assert evidence["retire_source"] == true
    end

    test "stops at the relocation cap" do
      context =
        context(
          primary: "us-east",
          serving: ["us-east"],
          relocations_in_window: 1,
          rollups: daily("FR", 30, 20)
        )

      assert Placement.evaluate(context) == :none
    end

    test "does not relocate an account with nothing to relocate from" do
      context = context(primary: nil, serving: [], rollups: daily("FR", 30, 20))

      assert Placement.evaluate(context) == :none
    end

    test "does not relocate into a region already retiring" do
      context =
        context(
          primary: "us-east",
          serving: ["us-east", "eu-central"],
          retiring: ["eu-central"],
          rollups: daily("FR", 30, 20)
        )

      assert Placement.evaluate(context) == :none
    end
  end

  describe "expand" do
    test "adds a region whose own traffic clears the absolute floor" do
      # Share-blind on purpose: a heavy second site earns a local instance even
      # while the first site dominates the account's mix.
      context =
        context(
          plan: :pro,
          primary: "us-east",
          serving: ["us-east"],
          rollups: daily("US-VA", 14, 500) ++ daily("FR", 14, 40)
        )

      assert {:expand, "eu-central", evidence} = Placement.evaluate(context)
      assert evidence["signal"] == "sustained_local_demand"
      assert evidence["runs_per_day"] >= 25
    end

    test "never expands an Air account" do
      context =
        context(
          plan: :air,
          primary: "us-east",
          serving: ["us-east"],
          rollups: daily("US-VA", 14, 500) ++ daily("FR", 14, 40)
        )

      assert Placement.evaluate(context) == :none
    end

    test "holds a region under the floor" do
      context =
        context(
          plan: :pro,
          primary: "us-east",
          serving: ["us-east"],
          rollups: daily("US-VA", 14, 500) ++ daily("FR", 14, 5)
        )

      assert Placement.evaluate(context) == :none
    end

    test "asks Enterprise for more than Pro before opening a region" do
      rollups = daily("US-VA", 14, 500) ++ daily("FR", 14, 30)

      assert {:expand, "eu-central", _evidence} =
               Placement.evaluate(context(plan: :pro, primary: "us-east", serving: ["us-east"], rollups: rollups))

      assert Placement.evaluate(context(plan: :enterprise, primary: "us-east", serving: ["us-east"], rollups: rollups)) ==
               :none
    end

    test "stops at the instance ceiling" do
      # The primary keeps the majority, so nothing relocates; what is refused
      # here is the fourth region on a plan that funds three.
      context =
        context(
          plan: :pro,
          primary: "us-east",
          serving: ["us-east", "eu-central", "ap-southeast"],
          rollups: daily("US-VA", 14, 500) ++ daily("US-OR", 14, 200) ++ daily("FR", 90, 20) ++ daily("SG", 90, 20)
        )

      assert Placement.evaluate(context) == :none
    end

    test "does not expand into a region it already holds" do
      context =
        context(
          plan: :pro,
          primary: "us-east",
          serving: ["us-east", "eu-central"],
          rollups: daily("US-VA", 14, 500) ++ daily("FR", 14, 40)
        )

      assert Placement.evaluate(context) == :none
    end
  end

  describe "retire" do
    test "gives up a secondary whose region has gone quiet" do
      context =
        context(
          plan: :pro,
          primary: "us-east",
          serving: ["us-east", "eu-central"],
          rollups: daily("US-VA", 90, 100) ++ daily("FR", 90, 1)
        )

      assert {:retire, "eu-central", evidence} = Placement.evaluate(context)
      assert evidence["signal"] == "demand_below_floor"
    end

    test "never retires the primary, however quiet its region has gone" do
      # Retirement reclaims a spare region; it does not take an account's cache
      # away. An account quiet everywhere keeps the one instance it has.
      context =
        context(
          plan: :pro,
          primary: "eu-central",
          serving: ["eu-central"],
          rollups: daily("FR", 90, 1)
        )

      assert Placement.evaluate(context) == :none
    end

    test "leaves a secondary that is still busy" do
      context =
        context(
          plan: :pro,
          primary: "us-east",
          serving: ["us-east", "eu-central"],
          rollups: daily("US-VA", 90, 100) ++ daily("FR", 90, 40)
        )

      assert Placement.evaluate(context) == :none
    end

    test "does not retire the same region twice" do
      context =
        context(
          plan: :pro,
          primary: "us-east",
          serving: ["us-east", "eu-central"],
          retiring: ["eu-central"],
          rollups: daily("US-VA", 90, 100) ++ daily("FR", 90, 1)
        )

      assert Placement.evaluate(context) == :none
    end

    test "gives up nothing when the account has no attributed traffic at all" do
      # Before origins are being attributed, every account looks like this. An
      # account nobody could locate is not one whose regions are misplaced, and
      # reading it as one would retire every secondary in the fleet.
      context =
        context(
          plan: :pro,
          primary: "us-east",
          serving: ["us-east", "eu-central"],
          held_since: %{"eu-central" => Date.add(@today, -120)},
          rollups: []
        )

      assert Placement.evaluate(context) == :none
    end

    test "does not give up a region expansion would reopen on the next sweep" do
      # The two floors span different windows, so a region quiet for months and
      # busy for the last fortnight sits under the retirement total while being
      # actively used.
      quiet_then_busy = for offset <- 0..89, do: rollup("FR", Date.add(@today, -offset), if(offset < 14, do: 25, else: 0))

      context =
        context(
          plan: :pro,
          primary: "us-east",
          serving: ["us-east", "eu-central"],
          held_since: %{"eu-central" => Date.add(@today, -120)},
          rollups: daily("US-VA", 90, 500) ++ quiet_then_busy
        )

      assert Placement.evaluate(context) == :none
    end

    test "does not give up a region younger than the retirement window" do
      # A region opened on a fortnight's traffic carries less than the
      # retirement window's worth of runs on the day it opens. Without the age
      # gate it would be given up immediately and reopened by the same evidence
      # the next fortnight.
      context =
        context(
          plan: :pro,
          primary: "us-east",
          serving: ["us-east", "eu-central"],
          held_since: %{"eu-central" => Date.add(@today, -14)},
          rollups: daily("US-VA", 90, 500) ++ daily("FR", 14, 10)
        )

      assert Placement.evaluate(context) == :none
    end

    test "gives it up once it has had the window and stayed quiet" do
      context =
        context(
          plan: :pro,
          primary: "us-east",
          serving: ["us-east", "eu-central"],
          held_since: %{"eu-central" => Date.add(@today, -120)},
          rollups: daily("US-VA", 90, 500) ++ daily("FR", 14, 10)
        )

      assert {:retire, "eu-central", _evidence} = Placement.evaluate(context)
    end

    test "the gap between the two floors is what keeps a region from flapping" do
      # A region between the retirement floor and the expansion floor is left
      # exactly as it is, whichever side it is currently on.
      between = daily("US-VA", 90, 500) ++ daily("FR", 90, 15)

      assert Placement.evaluate(
               context(plan: :pro, primary: "us-east", serving: ["us-east", "eu-central"], rollups: between)
             ) == :none

      assert Placement.evaluate(context(plan: :pro, primary: "us-east", serving: ["us-east"], rollups: between)) == :none
    end
  end

  test "an account with no traffic anywhere is left alone" do
    assert Placement.evaluate(context(primary: "us-east", serving: ["us-east"], rollups: [])) == :none
  end

  test "unattributed traffic decides nothing" do
    # Only rollups exist for origins the edge could place, so an account whose
    # requests were never attributed simply has no rows and no verdict.
    assert Placement.evaluate(context(primary: "us-east", serving: ["us-east"], rollups: [])) == :none
  end

  test "window_days/1 covers the longest span the policy reads" do
    assert Placement.window_days() == 90
  end

  defp context(overrides) do
    Enum.into(overrides, %{
      plan: :air,
      rollups: [],
      permitted: @permitted,
      primary: nil,
      serving: [],
      retiring: [],
      held_since: %{},
      relocations_in_window: 0,
      today: @today
    })
  end

  defp daily(origin, days, runs) do
    for offset <- 0..(days - 1), do: rollup(origin, Date.add(@today, -offset), runs)
  end

  defp rollup(origin, date, runs) do
    %{origin: origin, date: date, run_count: runs, demand_count: 0}
  end
end
