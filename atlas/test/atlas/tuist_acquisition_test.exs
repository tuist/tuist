defmodule Atlas.TuistAcquisitionTest do
  use ExUnit.Case, async: true

  alias Atlas.TuistAcquisition

  @range {~D[2026-09-01], ~D[2026-09-07]}

  # The landings query returns its groups as JSON in one row.
  defp ch_query(rows), do: fn _sql, _opts -> {:ok, %{"rows" => [%{"groups" => JSON.encode!(rows)}]}} end

  defp pg_query(groups, subscriptions \\ []) do
    fn _sql, _opts ->
      {:ok, %{"rows" => [%{"groups" => JSON.encode!(groups), "subscriptions" => JSON.encode!(subscriptions)}]}}
    end
  end

  defp funnel(landings, signups, opts \\ []) do
    TuistAcquisition.funnel(
      @range,
      opts ++ [configured?: fn -> true end, ch_query: ch_query(landings), pg_query: pg_query(signups)]
    )
  end

  @landings [
    %{"day" => "2026-09-01", "source" => "chatgpt.com", "medium" => "", "campaign" => "hub", "c" => "40"},
    %{"day" => "2026-09-03", "source" => "chatgpt.com", "medium" => "", "campaign" => "hub", "c" => 60},
    %{"day" => "2026-09-02", "source" => "newsletter", "medium" => "email", "campaign" => "", "c" => 5}
  ]

  @signups [
    %{
      "day" => "2026-09-02",
      "source" => "chatgpt.com",
      "medium" => "",
      "campaign" => "hub",
      "signups" => 4,
      "customers" => 1
    },
    %{"day" => "2026-09-04", "source" => "", "medium" => "", "campaign" => "", "signups" => 10, "customers" => 2},
    %{
      "day" => "2026-09-05",
      "source" => "news.ycombinator.com",
      "medium" => "referral",
      "campaign" => "",
      "signups" => 3,
      "customers" => 0
    }
  ]

  test "joins landings and signups per channel and keeps unattributed signups out of attributed totals" do
    assert {:ok, funnel} = funnel(@landings, @signups)

    assert funnel.totals == %{landings: 105, signups: 17, attributed_signups: 7, customers: 3}

    assert %{landings: 100, signups: 4, customers: 1} =
             Enum.find(funnel.channels, &(&1.source == "chatgpt.com"))

    assert %{landings: 0, signups: 3} = Enum.find(funnel.channels, &(&1.source == "news.ycombinator.com"))
    assert %{landings: 5, signups: 0} = Enum.find(funnel.channels, &(&1.source == "newsletter"))
    # Sorted by signups first.
    assert hd(funnel.channels).source == ""
    assert funnel.sources == ["chatgpt.com", "news.ycombinator.com", "newsletter"]
  end

  test "totals the equally long window before for trends, without charting or listing it" do
    earlier = [
      %{"day" => "2026-08-30", "source" => "chatgpt.com", "medium" => "", "campaign" => "", "c" => 7},
      %{"day" => "2026-08-25", "source" => "github.com", "medium" => "", "campaign" => "", "c" => 2}
    ]

    test_pid = self()

    ch_query = fn _sql, opts ->
      send(test_pid, {:params, opts[:params]})
      ch_query(@landings ++ earlier).(nil, nil)
    end

    assert {:ok, funnel} = funnel([], @signups, ch_query: ch_query)
    assert_received {:params, %{"previous_ts" => "2026-08-25 00:00:00", "end_ts" => "2026-09-08 00:00:00"}}

    assert funnel.previous.landings == 9
    assert funnel.totals.landings == 105
    refute "github.com" in funnel.sources

    assert {:ok, %{previous: %{landings: 7}}} = funnel([], @signups, ch_query: ch_query, source: "chatgpt.com")
  end

  test "tells the ads of one campaign apart and ties each subscription to its ad" do
    landings = [
      %{
        "day" => "2026-09-01",
        "source" => "linkedin",
        "medium" => "paid_social",
        "campaign" => "launch",
        "content" => "carousel-a",
        "c" => 30
      },
      %{
        "day" => "2026-09-01",
        "source" => "linkedin",
        "medium" => "paid_social",
        "campaign" => "launch",
        "content" => "video-b",
        "c" => 10
      }
    ]

    signups = [
      %{
        "day" => "2026-09-02",
        "source" => "linkedin",
        "medium" => "paid_social",
        "campaign" => "launch",
        "content" => "video-b",
        "signups" => 2,
        "customers" => 1
      }
    ]

    subscriptions = [
      %{
        "account" => "acme",
        "plan" => "pro",
        "status" => "active",
        "subscribed_on" => "2026-09-05",
        "signed_up_on" => "2026-09-02",
        "source" => "linkedin",
        "medium" => "paid_social",
        "campaign" => "launch",
        "content" => "video-b"
      },
      %{
        "account" => "beta",
        "plan" => "enterprise",
        "status" => "past_due",
        "subscribed_on" => "2026-09-04",
        "signed_up_on" => "2026-09-03",
        "source" => "",
        "medium" => "",
        "campaign" => "",
        "content" => ""
      }
    ]

    assert {:ok, funnel} = funnel(landings, [], pg_query: pg_query(signups, subscriptions))

    assert %{landings: 10, signups: 2, customers: 1} = Enum.find(funnel.channels, &(&1.content == "video-b"))
    assert %{landings: 30, signups: 0} = Enum.find(funnel.channels, &(&1.content == "carousel-a"))

    assert [
             %{account: "acme", content: "video-b", subscribed_on: ~D[2026-09-05], signed_up_on: ~D[2026-09-02]},
             %{account: "beta", plan: "enterprise", source: ""}
           ] = funnel.subscriptions

    assert {:ok, %{subscriptions: [%{account: "acme"}]}} =
             funnel(landings, [], pg_query: pg_query(signups, subscriptions), source: "linkedin")
  end

  test "narrows to one campaign and rates its effectiveness" do
    landings = [
      %{
        "day" => "2026-09-01",
        "source" => "linkedin",
        "medium" => "paid_social",
        "campaign" => "launch",
        "content" => "a",
        "c" => 60
      },
      %{
        "day" => "2026-09-03",
        "source" => "google",
        "medium" => "cpc",
        "campaign" => "launch",
        "content" => "b",
        "c" => 40
      },
      %{
        "day" => "2026-09-02",
        "source" => "newsletter",
        "medium" => "email",
        "campaign" => "2026-09",
        "content" => "",
        "c" => 500
      }
    ]

    signups = [
      %{
        "day" => "2026-09-02",
        "source" => "linkedin",
        "medium" => "paid_social",
        "campaign" => "launch",
        "content" => "a",
        "signups" => 3,
        "customers" => 1
      },
      %{
        "day" => "2026-09-04",
        "source" => "google",
        "medium" => "cpc",
        "campaign" => "launch",
        "content" => "b",
        "signups" => 7,
        "customers" => 1
      },
      %{
        "day" => "2026-09-04",
        "source" => "newsletter",
        "medium" => "email",
        "campaign" => "2026-09",
        "content" => "",
        "signups" => 9,
        "customers" => 0
      }
    ]

    subscription = fn account, campaign, signed_up_on, subscribed_on, plan ->
      %{
        "account" => account,
        "plan" => plan,
        "status" => "active",
        "signed_up_on" => signed_up_on,
        "subscribed_on" => subscribed_on,
        "source" => "google",
        "medium" => "cpc",
        "campaign" => campaign,
        "content" => "b"
      }
    end

    subscriptions = [
      subscription.("a", "launch", "2026-09-02", "2026-09-03", "pro"),
      subscription.("b", "launch", "2026-09-04", "2026-09-07", "enterprise"),
      subscription.("c", "2026-09", "2026-09-04", "2026-09-04", "pro")
    ]

    assert {:ok, all} = funnel(landings, [], pg_query: pg_query(signups, subscriptions))

    assert [%{campaign: "launch", landings: 100, signups: 10, ads: ["a", "b"]}, %{campaign: "2026-09", signups: 9}] =
             all.campaigns

    assert {:ok, launch} = funnel(landings, [], pg_query: pg_query(signups, subscriptions), campaign: "launch")
    assert launch.totals == %{landings: 100, signups: 10, attributed_signups: 10, customers: 2}
    assert launch.sources == ["google", "linkedin"]
    assert Enum.map(launch.subscriptions, & &1.account) == ["a", "b"]

    assert launch.effectiveness == %{
             signup_rate: 0.1,
             customer_rate: 0.2,
             landings_per_customer: 50.0,
             median_days_to_subscribe: 2.0,
             mean_days_to_subscribe: 2.0,
             plans: %{"pro" => 1, "enterprise" => 1},
             first_active_on: ~D[2026-09-01],
             last_active_on: ~D[2026-09-04],
             top_source: "google",
             top_ad: "b"
           }
  end

  test "lists and rates every subscription of the narrowed funnel" do
    subscription = fn index, source ->
      %{
        "account" => "account-#{index}",
        "plan" => if(source == "chatgpt.com", do: "enterprise", else: "pro"),
        "status" => "active",
        "signed_up_on" => "2026-09-01",
        "subscribed_on" => if(source == "chatgpt.com", do: "2026-09-05", else: "2026-09-02"),
        "source" => source,
        "medium" => "",
        "campaign" => "",
        "content" => ""
      }
    end

    subscriptions =
      Enum.map(1..600, &subscription.(&1, "newsletter")) ++ Enum.map(601..620, &subscription.(&1, "chatgpt.com"))

    assert {:ok, all} = funnel([], [], pg_query: pg_query([], subscriptions))
    assert length(all.subscriptions) == 620
    assert all.effectiveness.plans == %{"pro" => 600, "enterprise" => 20}

    assert {:ok, chatgpt} = funnel([], [], pg_query: pg_query([], subscriptions), source: "chatgpt.com")
    assert length(chatgpt.subscriptions) == 20
    assert chatgpt.effectiveness.median_days_to_subscribe == 4
  end

  test "reads landings bucketed by the chart's granularity from one row" do
    test_pid = self()

    ch_query = fn sql, opts ->
      send(test_pid, {:landings_query, sql, opts[:limit]})
      ch_query([%{"day" => "2026-06-08", "source" => "chatgpt.com", "c" => "3"}]).(sql, opts)
    end

    assert {:ok, funnel} =
             TuistAcquisition.funnel({~D[2026-06-03], ~D[2026-11-26]},
               configured?: fn -> true end,
               ch_query: ch_query,
               pg_query: pg_query([])
             )

    assert_received {:landings_query, sql, 1}
    assert sql =~ "greatest(toMonday(inserted_at)"
    assert funnel.granularity == :week
    assert funnel.totals.landings == 3
  end

  test "fills every day of the window" do
    assert {:ok, %{granularity: :day, series: series}} = funnel(@landings, @signups)

    assert series.landings == [
             {~D[2026-09-01], 40},
             {~D[2026-09-02], 5},
             {~D[2026-09-03], 60},
             {~D[2026-09-04], 0},
             {~D[2026-09-05], 0},
             {~D[2026-09-06], 0},
             {~D[2026-09-07], 0}
           ]

    assert Enum.map(series.attributed_signups, &elem(&1, 1)) == [0, 4, 0, 0, 3, 0, 0]
  end

  test "narrows every figure to one source" do
    assert {:ok, funnel} = funnel(@landings, @signups, source: "chatgpt.com")

    assert funnel.totals == %{landings: 100, signups: 4, attributed_signups: 4, customers: 1}
    assert [%{source: "chatgpt.com"}] = funnel.channels
  end

  test "reports a server that is not configured or a failing query" do
    assert {:error, :not_configured} = TuistAcquisition.funnel(@range, configured?: fn -> false end)

    assert {:error, "boom"} =
             TuistAcquisition.funnel(@range,
               configured?: fn -> true end,
               ch_query: fn _sql, _opts -> {:error, "boom"} end,
               pg_query: pg_query([])
             )
  end
end
