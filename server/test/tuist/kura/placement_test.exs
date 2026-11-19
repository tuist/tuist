defmodule Tuist.Kura.PlacementTest do
  use ExUnit.Case, async: true

  alias Tuist.Kura.Placement

  @today ~D[2026-08-26]
  @permitted ["us-east", "us-west", "eu-west", "ap-southeast"]

  describe "correct initial placement" do
    test "corrects a guess on a short window at a higher bar" do
      context =
        context(
          plan: :pro,
          primary: "us-east",
          primary_decided?: false,
          serving: ["us-east"],
          held_since: %{"us-east" => Date.add(@today, -3)},
          rollups: daily("FR", 7, 90) ++ daily("US-VA", 7, 10)
        )

      assert {:correct, "us-east", "eu-west", evidence} = Placement.evaluate(context)
      assert evidence["signal"] == "initial_placement_missed"
    end

    test "corrects a guess on a single day of traffic" do
      # The rung fires at most once per account, so waiting for days to
      # accumulate buys no protection against flapping, and every build until
      # they do is served from the wrong side of an ocean. An account that
      # builds a few days a week could also fail to accumulate them before
      # `within_days` closed the rung, which is the outcome it exists to
      # prevent.
      context =
        context(
          primary: "us-east",
          primary_decided?: false,
          serving: ["us-east"],
          held_since: %{"us-east" => Date.add(@today, -1)},
          rollups: [rollup("FR", @today, 40)]
        )

      assert {:correct, "us-east", "eu-west", evidence} = Placement.evaluate(context)
      assert evidence["signal"] == "initial_placement_missed"
      assert evidence["active_days"] == 1
    end

    test "does not correct on a single day too quiet to mean anything" do
      # One day is enough only once it carries a working day's traffic. The
      # volume floor is what still separates a team that moved from a couple
      # of runs someone tried out at a conference.
      context =
        context(
          primary: "us-east",
          primary_decided?: false,
          serving: ["us-east"],
          held_since: %{"us-east" => Date.add(@today, -1)},
          rollups: [rollup("FR", @today, 30)]
        )

      refute match?({:correct, _from, _to, _evidence}, Placement.evaluate(context))
    end

    test "does not correct a placement something decided" do
      # The rung replaces a guess. An applied relocation, an operator pin or
      # the backfill are decisions, and a decision is not corrected on a week.
      context =
        context(
          plan: :pro,
          primary: "us-east",
          primary_decided?: true,
          serving: ["us-east"],
          held_since: %{"us-east" => Date.add(@today, -3)},
          rollups: daily("FR", 7, 90) ++ daily("US-VA", 7, 10)
        )

      refute match?({:correct, _from, _to, _evidence}, Placement.evaluate(context))
    end

    test "does not correct a guess that has stopped being new" do
      context =
        context(
          plan: :pro,
          primary: "us-east",
          primary_decided?: false,
          serving: ["us-east"],
          held_since: %{"us-east" => Date.add(@today, -20)},
          rollups: daily("FR", 7, 90) ++ daily("US-VA", 7, 10)
        )

      refute match?({:correct, _from, _to, _evidence}, Placement.evaluate(context))
    end

    test "does not correct on a majority the slower rung would accept" do
      # Acting on a week of evidence demands more than acting on a month: a
      # 65/35 split moves a settled primary but is not enough to overturn a
      # guess this early.
      context =
        context(
          plan: :pro,
          primary: "us-east",
          primary_decided?: false,
          serving: ["us-east"],
          held_since: %{"us-east" => Date.add(@today, -3)},
          rollups: daily("FR", 7, 65) ++ daily("US-VA", 7, 35)
        )

      refute match?({:correct, _from, _to, _evidence}, Placement.evaluate(context))
    end

    test "runs alone never move a settled primary" do
      # Runs count where builds report from, which is not where the cache is
      # used on much of the fleet. Only the guess a first placement is reads
      # them.
      context =
        context(
          plan: :pro,
          primary: "us-east",
          serving: ["us-east"],
          rollups: daily("FR", 30, 20) ++ daily("US-VA", 30, 5)
        )

      assert Placement.evaluate(context) == :none
    end
  end

  describe "plan cap" do
    test "never opens a second Air region, however busy its second site" do
      context =
        context(
          plan: :air,
          primary: "us-east",
          serving: ["us-east"],
          rollups: daily_hits("US-VA", 14, 15_000) ++ daily_hits("FR", 14, 5_000),
          served: %{"us-east" => served_daily(28, 20_000)},
          reported: reported(["us-east"], 28),
          reserved_gib: %{"us-east" => 16},
          projected_gib: %{"eu-west" => 16}
        )

      assert Placement.evaluate(context) == :none
    end

    test "gives up the quietest region an Air account holds beyond its primary" do
      # Held from when Air funded two. The primary stays even though eu-west
      # is busier; the least used secondary goes first.
      context =
        context(
          plan: :air,
          primary: "us-east",
          serving: ["us-east", "eu-west", "ap-southeast"],
          rollups: daily_hits("US-VA", 28, 100) ++ daily_hits("FR", 28, 60) ++ daily_hits("SG", 28, 30)
        )

      assert {:retire, "ap-southeast", evidence} = Placement.evaluate(context)
      assert evidence["signal"] == "over_instance_cap"

      assert Placement.evaluate(%{context | retiring: ["ap-southeast"]}) ==
               {:retire, "eu-west", %{evidence | "region_traffic" => 1_680}}

      assert Placement.evaluate(%{context | retiring: ["ap-southeast", "eu-west"]}) == :none
    end
  end

  describe "runs" do
    test "open no region however busy the second site" do
      context =
        context(
          plan: :pro,
          primary: "us-east",
          serving: ["us-east"],
          rollups: daily("US-VA", 14, 500) ++ daily("FR", 14, 40)
        )

      assert Placement.evaluate(context) == :none
      assert context |> Map.merge(served_only("us-east")) |> Placement.evaluate() == :none
    end

    test "retire no secondary however quiet its region" do
      # Over a quarter of runs eu-west is a region nobody builds from. Whether
      # it is used is what it served, which only the hits rungs read.
      context =
        context(
          plan: :pro,
          primary: "us-east",
          serving: ["us-east", "eu-west"],
          held_since: %{"eu-west" => Date.add(@today, -120)},
          rollups: daily("US-VA", 90, 100) ++ daily("FR", 90, 1)
        )

      assert Placement.evaluate(context) == :none
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
    assert Placement.window_days() == 28
  end

  describe "served hits" do
    test "moves the primary to the held region carrying the majority of hits, whatever the runs say" do
      # Builds reported from Amsterdam put the primary in eu-west, but the
      # cache traffic lands in us-central. The destination is already held and
      # warm, so following the hits costs no refill.
      context =
        context(
          plan: :enterprise,
          primary: "eu-west",
          serving: ["eu-west", "us-central", "us-east"],
          rollups: daily("NL", 30, 140) ++ daily("US-IL", 30, 80),
          served: %{
            "us-central" => served_daily(14, 30_000),
            "us-east" => served_daily(14, 2_000),
            "eu-west" => served_daily(14, 300)
          },
          reported: reported(["eu-west", "us-central", "us-east"], 28),
          reserved_gib: %{"eu-west" => 60, "us-central" => 60, "us-east" => 60}
        )

      assert {:relocate, "eu-west", "us-central", evidence} = Placement.evaluate(context)
      assert evidence["signal"] == "majority_of_hits_moved"
      assert evidence["share"] > 0.9
      # The region left behind served under 1% of the hits on a 60 GiB claim.
      assert evidence["retire_source"] == true
    end

    test "keeps the region it leaves when what it serves still pays for its claim" do
      context =
        context(
          plan: :enterprise,
          primary: "eu-west",
          serving: ["eu-west", "us-central"],
          served: %{"us-central" => served_daily(14, 30_000), "eu-west" => served_daily(14, 5_000)},
          reported: reported(["eu-west", "us-central"], 28),
          reserved_gib: %{"eu-west" => 60, "us-central" => 60}
        )

      assert {:relocate, "eu-west", "us-central", evidence} = Placement.evaluate(context)
      assert evidence["retire_source"] == false
    end

    test "does not move the primary onto a held region on runs the hits contradict" do
      # Without hits this is the runs rung's textbook relocation. The primary
      # serving five times what eu-west does says the runs are not where the
      # cache is used.
      context =
        context(
          plan: :pro,
          primary: "us-east",
          serving: ["us-east", "eu-west"],
          rollups: daily("FR", 30, 20) ++ daily("US-VA", 30, 5),
          served: %{"us-east" => served_daily(28, 20_000), "eu-west" => served_daily(28, 4_000)},
          reported: reported(["us-east", "eu-west"], 28),
          reserved_gib: %{"us-east" => 8, "eu-west" => 8}
        )

      assert Placement.evaluate(context) == :none
    end

    test "retires a secondary that served almost nothing for what it reserves" do
      context =
        context(
          plan: :enterprise,
          primary: "us-west",
          serving: ["us-west", "eu-east"],
          served: %{"us-west" => served_daily(28, 100_000), "eu-east" => served_daily(28, 300)},
          reported: reported(["us-west", "eu-east"], 28),
          reserved_gib: %{"us-west" => 256, "eu-east" => 256}
        )

      assert {:retire, "eu-east", evidence} = Placement.evaluate(context)
      assert evidence["signal"] == "hits_below_floor"
      assert evidence["reserved_gib"] == 256
      assert evidence["reported_days"] == 28
    end

    test "retires a secondary that served nothing at all" do
      context =
        context(
          plan: :enterprise,
          primary: "eu-west",
          serving: ["eu-west", "us-central"],
          served: %{"eu-west" => served_daily(28, 1_000)},
          reported: reported(["eu-west", "us-central"], 28),
          reserved_gib: %{"eu-west" => 50, "us-central" => 50}
        )

      assert {:retire, "us-central", evidence} = Placement.evaluate(context)
      assert evidence["region_hits"] == 0
    end

    test "keeps a secondary that is a sliver of a busy account but busy for its claim" do
      # 2% of the account, and still thirty thousand hits a day: a second site
      # the primary's volume must not be allowed to veto.
      context =
        context(
          plan: :enterprise,
          primary: "us-central",
          serving: ["us-central", "ap-southeast"],
          served: %{"us-central" => served_daily(28, 1_500_000), "ap-southeast" => served_daily(28, 30_000)},
          reported: reported(["us-central", "ap-southeast"], 28),
          reserved_gib: %{"us-central" => 128, "ap-southeast" => 128}
        )

      assert Placement.evaluate(context) == :none
    end

    test "does not retire a secondary on days it was not heard from" do
      context =
        context(
          plan: :enterprise,
          primary: "us-west",
          serving: ["us-west", "eu-east"],
          served: %{"us-west" => served_daily(28, 100_000)},
          reported: %{"us-west" => reported_dates(28), "eu-east" => reported_dates(10)},
          reserved_gib: %{"us-west" => 64, "eu-east" => 64}
        )

      assert Placement.evaluate(context) == :none
    end

    test "gives a secondary with nonzero hits the whole low-traffic window before judging it" do
      context =
        context(
          plan: :enterprise,
          primary: "us-west",
          serving: ["us-west", "eu-east"],
          held_since: %{"eu-east" => Date.add(@today, -10)},
          served: %{"us-west" => served_daily(28, 100_000), "eu-east" => served_daily(28, 1)},
          reported: reported(["us-west", "eu-east"], 28),
          reserved_gib: %{"us-west" => 64, "eu-east" => 64}
        )

      assert Placement.evaluate(context) == :none
    end

    test "judges a secondary per day the account used the cache, not per calendar day" do
      # Ten busy days out of twenty-eight. Spread over the calendar the
      # secondary looks under its 3,200-a-day floor; over the days anyone was
      # building it is above it.
      context =
        context(
          plan: :enterprise,
          primary: "us-east",
          serving: ["us-east", "us-west"],
          served: %{"us-east" => served_daily(10, 200_000), "us-west" => served_daily(10, 3_500)},
          reported: reported(["us-east", "us-west"], 28),
          reserved_gib: %{"us-east" => 128, "us-west" => 128}
        )

      assert Placement.evaluate(context) == :none
    end

    test "keeps a region that serves however few runs map to it" do
      # A handful of runs a day maps to eu-east. It serves five thousand hits a
      # day.
      context =
        context(
          plan: :enterprise,
          primary: "us-east",
          serving: ["us-east", "eu-east"],
          rollups: daily("US-VA", 90, 100) ++ daily("RO", 90, 2),
          served: %{"us-east" => served_daily(28, 80_000), "eu-east" => served_daily(28, 5_000)},
          reported: reported(["us-east", "eu-east"], 28),
          reserved_gib: %{"us-east" => 50, "eu-east" => 50}
        )

      assert Placement.evaluate(Map.delete(context, :served)) == :none
      assert Placement.evaluate(context) == :none
    end

    test "opens no region on runs, however busy the second site" do
      context =
        context(
          plan: :pro,
          primary: "us-east",
          serving: ["us-east"],
          rollups: daily("US-VA", 30, 1_500) ++ daily("FR", 30, 30),
          served: %{"us-east" => served_daily(28, 100_000)},
          reported: reported(["us-east"], 28),
          reserved_gib: %{"us-east" => 64}
        )

      assert Placement.evaluate(context) == :none
    end

    test "does not reopen a region it gave up until the reopening window has passed" do
      context =
        context(
          plan: :pro,
          primary: "us-east",
          serving: ["us-east"],
          rollups: daily_hits("US-VA", 14, 15_000) ++ daily_hits("FR", 14, 5_000),
          served: %{"us-east" => served_daily(28, 20_000)},
          reported: reported(["us-east"], 28),
          reserved_gib: %{"us-east" => 64},
          projected_gib: %{"eu-west" => 64}
        )

      assert Placement.evaluate(Map.put(context, :given_up, %{"eu-west" => Date.add(@today, -30)})) == :none

      assert {:expand, "eu-west", _evidence} =
               Placement.evaluate(Map.put(context, :given_up, %{"eu-west" => Date.add(@today, -91)}))
    end
  end

  describe "origin hits" do
    test "opens a region a real share of the account's hits come from" do
      context =
        context(
          plan: :pro,
          primary: "us-east",
          serving: ["us-east"],
          rollups: daily_hits("US-VA", 14, 15_000) ++ daily_hits("FR", 14, 5_000),
          served: %{"us-east" => served_daily(28, 20_000)},
          reported: reported(["us-east"], 28),
          reserved_gib: %{"us-east" => 128},
          projected_gib: %{"eu-west" => 128}
        )

      assert {:expand, "eu-west", evidence} = Placement.evaluate(context)
      assert evidence["signal"] == "projected_hits"
      assert evidence["share"] == 0.25
    end

    test "does not open a region on runs a sliver of the hits contradict" do
      # Thirty runs a day from Paris clears the runs floor; Paris is 2% of the
      # account's hits, and a fraction of what the region would reserve.
      context =
        context(
          plan: :pro,
          primary: "us-east",
          serving: ["us-east"],
          rollups:
            daily("US-VA", 30, 1_500) ++
              daily("FR", 30, 30) ++ daily_hits("US-VA", 14, 19_600) ++ daily_hits("FR", 14, 400),
          served: %{"us-east" => served_daily(28, 20_000)},
          reported: reported(["us-east"], 28),
          reserved_gib: %{"us-east" => 128},
          projected_gib: %{"eu-west" => 128}
        )

      assert Placement.evaluate(Map.delete(context, :served)) == :none
      assert Placement.evaluate(context) == :none
    end

    test "opens a cheap region on its rate when its share is small" do
      context =
        context(
          plan: :pro,
          primary: "us-east",
          serving: ["us-east"],
          rollups: daily_hits("US-VA", 14, 18_500) ++ daily_hits("FR", 14, 1_500),
          served: %{"us-east" => served_daily(28, 20_000)},
          reported: reported(["us-east"], 28),
          reserved_gib: %{"us-east" => 8},
          projected_gib: %{"eu-west" => 8}
        )

      assert {:expand, "eu-west", evidence} = Placement.evaluate(context)
      assert evidence["share"] < 0.1
    end

    test "opens nothing while too few of the account's hits carry an origin" do
      # A quarter of the hits carry an origin. Read as the account, Paris would
      # be 40% of it; the rest of the traffic says nothing about where it
      # comes from, and runs do not stand in for it.
      context =
        context(
          plan: :pro,
          primary: "us-east",
          serving: ["us-east"],
          rollups:
            daily("US-VA", 30, 100) ++
              daily("FR", 30, 30) ++ daily_hits("US-VA", 14, 3_000) ++ daily_hits("FR", 14, 2_000),
          served: %{"us-east" => served_daily(28, 20_000)},
          reported: reported(["us-east"], 28),
          reserved_gib: %{"us-east" => 128},
          projected_gib: %{"eu-west" => 128}
        )

      assert Placement.evaluate(context) == :none
    end

    test "moves the primary to a region it does not hold once most hits come from nearer it" do
      context =
        context(
          plan: :pro,
          primary: "us-east",
          serving: ["us-east"],
          rollups: daily_hits("FR", 14, 15_000) ++ daily_hits("US-VA", 14, 5_000),
          served: %{"us-east" => served_daily(28, 20_000)},
          reported: reported(["us-east"], 28),
          reserved_gib: %{"us-east" => 128},
          projected_gib: %{"eu-west" => 128}
        )

      assert {:relocate, "us-east", "eu-west", evidence} = Placement.evaluate(context)
      assert evidence["signal"] == "majority_of_origin_hits_moved"
      assert evidence["share"] == 0.75
      # The source still serves a quarter of the hits, which keeps it for Pro.
      # Air holds one region, so its primary moves and the source goes.
      assert evidence["retire_source"] == false

      assert {:relocate, "us-east", "eu-west", %{"retire_source" => true}} =
               Placement.evaluate(%{context | plan: :air})
    end

    test "does not move the primary on runs the hits contradict" do
      context =
        context(
          primary: "us-east",
          serving: ["us-east"],
          rollups: daily("FR", 30, 20) ++ daily("US-VA", 30, 5) ++ daily_hits("US-VA", 14, 20_000),
          served: %{"us-east" => served_daily(28, 20_000)},
          reported: reported(["us-east"], 28),
          reserved_gib: %{"us-east" => 16},
          projected_gib: %{"eu-west" => 16}
        )

      assert Placement.evaluate(Map.delete(context, :served)) == :none
      assert Placement.evaluate(context) == :none
    end

    test "does not reopen a region the hits closed, whatever its origins project" do
      context =
        context(
          plan: :pro,
          primary: "us-east",
          serving: ["us-east"],
          rollups: daily_hits("US-VA", 14, 15_000) ++ daily_hits("FR", 14, 5_000),
          served: %{"us-east" => served_daily(28, 20_000)},
          reported: reported(["us-east"], 28),
          reserved_gib: %{"us-east" => 128},
          projected_gib: %{"eu-west" => 128},
          given_up: %{"eu-west" => Date.add(@today, -30)}
        )

      assert Placement.evaluate(context) == :none
    end

    test "does not move the primary into a region the hits closed" do
      context =
        context(
          plan: :pro,
          primary: "us-east",
          serving: ["us-east"],
          rollups: daily_hits("FR", 14, 15_000) ++ daily_hits("US-VA", 14, 5_000),
          served: %{"us-east" => served_daily(28, 20_000)},
          reported: reported(["us-east"], 28),
          reserved_gib: %{"us-east" => 128},
          projected_gib: %{"eu-west" => 128},
          given_up: %{"eu-west" => Date.add(@today, -30)}
        )

      assert Placement.evaluate(context) == :none

      assert {:relocate, "us-east", "eu-west", _evidence} =
               Placement.evaluate(Map.put(context, :given_up, %{"eu-west" => Date.add(@today, -91)}))
    end
  end

  describe "zero-hit secondary retirement" do
    setup do
      context =
        context(
          plan: :enterprise,
          primary: "us-east",
          serving: ["us-east", "us-west"],
          held_since: %{"us-west" => Date.add(@today, -10)},
          served: %{"us-east" => served_daily(11, 1_000)},
          reported: %{"us-west" => for(offset <- 1..10, do: Date.add(@today, -offset))},
          reserved_gib: %{"us-east" => 128, "us-west" => 128}
        )

      %{context: context}
    end

    test "retires after ten complete reported days without hits", %{context: context} do
      assert {:retire, "us-west", evidence} = Placement.evaluate(context)
      assert evidence["signal"] == "zero_hits"
      assert evidence["window_days"] == 10
      assert evidence["reported_days"] == 10
      assert evidence["region_hits"] == 0
      assert evidence["reserved_gib"] == 128
    end

    test "does not count today as a complete reporting day", %{context: context} do
      context = put_in(context.reported["us-west"], reported_dates(10))
      assert Placement.evaluate(context) == :none
    end

    test "does not treat a telemetry gap or duplicate report as a zero-hit day", %{
      context: context
    } do
      dates = context.reported["us-west"]
      dates = [hd(dates) | List.delete(dates, Date.add(@today, -5))]
      context = put_in(context.reported["us-west"], dates)
      assert Placement.evaluate(context) == :none
    end

    test "a hit on any day in the window blocks early retirement", %{context: context} do
      for offset <- 1..10 do
        context = put_in(context.served["us-west"], [{Date.add(@today, -offset), 1}])
        assert Placement.evaluate(context) == :none
      end
    end

    test "a hit today blocks early retirement", %{context: context} do
      context = put_in(context.served["us-west"], [{@today, 1}])
      assert Placement.evaluate(context) == :none
    end

    test "older hits do not extend the zero-hit window", %{context: context} do
      context = put_in(context.served["us-west"], [{Date.add(@today, -11), 1}])
      assert {:retire, "us-west", _evidence} = Placement.evaluate(context)
    end

    test "does not retire an instance younger than ten days", %{context: context} do
      context = put_in(context.held_since["us-west"], Date.add(@today, -9))
      assert Placement.evaluate(context) == :none
    end

    test "requires a known instance age", %{context: context} do
      assert Placement.evaluate(%{context | held_since: %{}}) == :none
    end

    test "never retires the primary or the only serving instance", %{context: context} do
      assert Placement.evaluate(%{context | primary: "us-west"}) == :none
      context = %{context | primary: "us-west", serving: ["us-west"]}
      assert Placement.evaluate(context) == :none
    end

    test "loads enough history for a complete-day retirement window" do
      policy = put_in(Placement.served_policy().retire_zero_hits.window_days, 35)
      assert Placement.served_window_days(policy) == 36
    end

    test "does not retire a region already retiring", %{context: context} do
      assert Placement.evaluate(%{context | retiring: ["us-west"]}) == :none
    end

    test "requires hits in another region that is staying", %{context: context} do
      assert Placement.evaluate(%{context | served: %{}}) == :none
      assert Placement.evaluate(%{context | retiring: ["us-east"]}) == :none
    end

    test "requires the served-hits rollout context", %{context: context} do
      assert context |> Map.delete(:served) |> Placement.evaluate() == :none
    end
  end

  defp context(overrides) do
    Enum.into(overrides, %{
      plan: :air,
      rollups: [],
      permitted: @permitted,
      primary: nil,
      # Settled by default: these describe placements that were decided, so the
      # correction rung is not the one under test unless a case says so.
      primary_decided?: true,
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

  defp daily_hits(origin, days, hits) do
    for offset <- 0..(days - 1),
        do: %{origin: origin, date: Date.add(@today, -offset), run_count: 0, demand_count: 0, hit_count: hits}
  end

  defp served_only(region) do
    %{served: %{region => served_daily(28, 20_000)}, reported: reported([region], 28), reserved_gib: %{region => 64}}
  end

  defp served_daily(days, hits) do
    for offset <- 0..(days - 1), do: {Date.add(@today, -offset), hits}
  end

  defp reported(regions, days), do: Map.new(regions, &{&1, reported_dates(days)})

  defp reported_dates(days), do: for(offset <- 0..(days - 1), do: Date.add(@today, -offset))
end
