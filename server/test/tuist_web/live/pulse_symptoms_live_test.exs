defmodule TuistWeb.PulseSymptomsLiveTest do
  use TuistTestSupport.Cases.ConnCase, async: true
  use TuistTestSupport.Cases.LiveCase, async: true
  use Mimic

  import Phoenix.LiveViewTest

  alias Tuist.Environment
  alias Tuist.Pulse.Investigations.Investigation
  alias Tuist.Pulse.SymptomMute
  alias Tuist.Pulse.SymptomOutcome
  alias Tuist.Repo
  alias TuistTestSupport.Fixtures.AccountsFixtures
  alias TuistTestSupport.Fixtures.PulseFixtures
  alias TuistWeb.Errors.NotFoundError

  setup %{conn: conn} do
    user = AccountsFixtures.user_fixture()
    organization = AccountsFixtures.organization_fixture(creator: user)
    account = organization.account
    stub(Environment, :pulse_config, fn -> [account_id: account.id] end)
    stub(Tuist.FeatureFlags, :pulse_enabled?, fn _ -> true end)
    %{conn: log_in_user(conn, user), user: user, account: account}
  end

  defp id(i), do: "0193a1f0-0000-7000-8000-" <> String.pad_leading("#{i}", 12, "0")

  defp revision(i, overrides) do
    now = DateTime.utc_now()

    PulseFixtures.symptom_revision(
      Map.merge(
        %{
          "symptom_id" => id(i),
          "seq" => i,
          "title" => "Title #{i}",
          "opened_at" => DateTime.to_iso8601(DateTime.add(now, -i * 60)),
          "updated_at" => DateTime.to_iso8601(DateTime.add(now, -i * 60))
        },
        overrides
      )
    )
  end

  test "lists mirrored symptoms with why they surfaced, linked to their page", ctx do
    {:ok, _} =
      PulseFixtures.mirror_symptoms(ctx.account, [
        revision(1, %{
          "tier" => "page",
          "title" => "<script>boom</script>",
          "phenomena" => [
            %{"phenomenon" => "novelty", "nats" => 3.0, "sources" => ["log.novelty", "error.novelty"]},
            %{"phenomenon" => "request_errors", "nats" => 1.0, "sources" => ["log.template_share"]}
          ]
        }),
        revision(2, %{
          "state" => "resolved",
          "transition" => "resolved",
          "tier" => "board",
          "impact" => %{"unit" => "failed_requests_per_min", "rate" => 12.5}
        })
      ])

    {:ok, view, _} = live(ctx.conn, "/#{ctx.account.name}/pulse")
    html = render_async(view, 5_000)

    assert has_element?(view, "#symptoms-widget-opened")
    sources = "#symptom-#{id(1)} [data-part='symptom-sources']"
    assert has_element?(view, "#{sources} .noora-badge", "Logs")
    assert has_element?(view, "#{sources} .noora-badge", "Errors")
    assert view |> element(sources) |> render() |> Floki.parse_fragment!() |> Floki.find(".noora-badge") |> length() == 2
    assert has_element?(view, "#symptom-#{id(2)} [data-part='symptom-sources'] .noora-badge", "Traces")
    refute has_element?(view, "#symptoms-table th", "Signals")
    assert has_element?(view, "#symptoms-table th", "Sources")
    refute has_element?(view, "#symptoms-table [data-part='issue-cell'] .noora-badge")
    assert has_element?(view, "#symptoms-table th", "Observation")
    assert has_element?(view, "#symptoms-table th", "Confidence")
    assert has_element?(view, "#symptoms-table [role='meter'][aria-label='Confidence'][aria-valuenow='42.0']")
    assert has_element?(view, "#symptoms-table", "42%")
    assert has_element?(view, "#symptoms-table td", "12 failed requests/min")
    assert has_element?(view, "#symptoms-table td", "12.5 failed requests/min")
    refute has_element?(view, "#symptoms-table td", "12.0 failed requests/min")
    refute has_element?(view, "#symptoms-table", "failed_requests_per_min")
    assert has_element?(view, "#symptoms-table", "Updated")
    assert has_element?(view, "#symptoms-table", "Opened")
    refute has_element?(view, "#symptoms-table", "Page")
    refute has_element?(view, "#symptoms-table", "Board")
    refute has_element?(view, "#symptoms-table", "Audit")
    assert has_element?(view, "#symptoms-table", "POST /api/runs")
    assert has_element?(view, "#symptoms-search-form")
    assert has_element?(view, "#symptoms-sort-by")
    assert has_element?(view, "#symptoms-filter-dropdown")
    # Titles are untrusted: rendered escaped.
    refute html =~ "<script>boom"
    assert html =~ "&lt;script&gt;boom"
    assert has_element?(view, "#symptoms-table [href='/#{ctx.account.name}/pulse/symptoms/#{id(1)}']")
  end

  test "filters by state, tier and phenomenon; search, sort and pages come from the URL", ctx do
    revisions =
      for(i <- 1..21, do: revision(i, %{})) ++
        [
          revision(22, %{
            "state" => "resolved",
            "transition" => "resolved",
            "tier" => "page",
            "phenomena" => [%{"phenomenon" => "saturation", "nats" => 3.0}],
            "p_degraded" => 0.99
          })
        ]

    {:ok, _} = PulseFixtures.mirror_symptoms(ctx.account, revisions)
    base = "/#{ctx.account.name}/pulse"
    {:ok, view, _} = live(ctx.conn, base)
    render_async(view, 5_000)

    first_row = fn -> view |> element("#symptoms-table tbody tr:first-child") |> render() end
    assert first_row.() =~ ~r/Title 1\s*</
    assert has_element?(view, "#symptoms-next-page")

    for filter <- [
          "filter_state_op===&filter_state_val=resolved",
          "filter_tier_op===&filter_tier_val=page",
          "filter_phenomenon_op===&filter_phenomenon_val=saturation"
        ] do
      render_patch(view, base <> "?" <> filter)
      render_async(view, 5_000)
      assert has_element?(view, "[data-part='active-filters']")
      assert has_element?(view, "#symptoms-table", "Title 22")
      refute has_element?(view, "#symptoms-table", ~r/Title 1(?!\d)/)
    end

    render_patch(view, base <> "?sort_by=p_degraded&sort_order=desc")
    render_async(view, 5_000)
    assert first_row.() =~ "Title 22"

    render_patch(view, base <> "?page=2")
    render_async(view, 5_000)
    assert first_row.() =~ "Title 21"

    render_patch(view, base <> "?search=Title%2017")
    render_async(view, 5_000)
    assert has_element?(view, "#symptoms-table", "Title 17")
    refute has_element?(view, "#symptoms-table", "Title 18")

    # Unknown values are dropped rather than failing the page.
    render_patch(view, base <> "?page=abc&sort_by=title&filter_tier_op===&filter_tier_val=urgent")
    render_async(view, 5_000)
    refute has_element?(view, "#symptoms-error")
    refute has_element?(view, "[data-part='active-filters']")
    assert first_row.() =~ ~r/Title 1\s*</
  end

  test "Pulse is the selected page with signals nested beneath it", ctx do
    {:ok, _} = PulseFixtures.mirror_symptoms(ctx.account, [revision(1, %{})])
    item = "#sidebar-pulse [data-part='header'][data-selected] a[href='/#{ctx.account.name}/pulse']"

    for path <- ["/#{ctx.account.name}/pulse", "/#{ctx.account.name}/pulse/symptoms/#{id(1)}"] do
      {:ok, view, _} = live(ctx.conn, path)
      assert has_element?(view, item, "Pulse")
      refute has_element?(view, "#sidebar-pulse a[data-part='item']", "Symptoms")
      assert has_element?(view, "#sidebar-pulse a[href='/#{ctx.account.name}/pulse/metrics']", "Metrics")
    end
  end

  test "shows an empty state when nothing was mirrored", ctx do
    {:ok, view, _} = live(ctx.conn, "/#{ctx.account.name}/pulse")
    render_async(view, 5_000)
    assert has_element?(view, "#symptoms-empty", "Nothing has needed investigation yet.")
  end

  test "the detail page shows history, evidence and the suspected change as untrusted text", ctx do
    {:ok, _} =
      PulseFixtures.mirror_symptoms(ctx.account, [
        revision(1, %{}),
        revision(2, %{
          "seq" => 2,
          "symptom_id" => id(1),
          "revision" => 2,
          "tier" => "page",
          "transition" => "escalated",
          "suspected_change" => %{"kind" => "deploy", "ref" => "abc123", "at" => "2026-11-16T11:58:00Z"},
          "brief_ref" => "brief-7",
          "evidence" => %{
            "series_refs" => [%{"query" => "rate(errors[1m])", "from" => 0, "to" => 0, "baseline" => [0, 0]}],
            "example_ids" => ["trace-1"],
            "masked_excerpts" => ["<img src=x onerror=alert(1)> at <path>"]
          }
        })
      ])

    {:ok, view, html} = live(ctx.conn, "/#{ctx.account.name}/pulse/symptoms/#{id(1)}")

    refute has_element?(view, "#pulse-symptom-tabs")
    assert has_element?(view, "#pulse-symptom-revisions", "History")
    refute has_element?(view, "#pulse-symptom-detail table")
    assert has_element?(view, "#pulse-symptom-history li:first-child", "Escalated")
    assert has_element?(view, "#pulse-symptom-history li time[datetime][title]")

    refute has_element?(view, "#pulse-symptom-summary", "brief-7")
    refute has_element?(view, "#pulse-symptom-summary", "nats")
    assert has_element?(view, "#pulse-symptom-history li", "Escalated")
    assert has_element?(view, "#pulse-symptom-history li", "Opened")
    assert has_element?(view, "#pulse-symptom-change", "abc123")
    assert has_element?(view, "#pulse-symptom-change", "2026-11-16 11:58 UTC")
    refute has_element?(view, "#pulse-symptom-summary", "brief-7")
    assert has_element?(view, "#pulse-symptom-evidence", "rate(errors[1m])")
    assert has_element?(view, "#pulse-symptom-evidence", "trace-1")
    assert has_element?(view, "#pulse-symptom-history")
    assert has_element?(view, "#pulse-symptom-technical #pulse-symptom-evidence", "rate(errors[1m])")
    refute has_element?(view, "#pulse-symptom-summary", "nats")
    refute html =~ "<img src=x"
    assert html =~ "&lt;img src=x onerror=alert(1)&gt;"
  end

  test "keeps source badges visible without brief or empty diagnostic cards", ctx do
    {:ok, _} =
      PulseFixtures.mirror_symptoms(ctx.account, [
        revision(1, %{
          "tier" => "audit",
          "phenomena" => [
            %{
              "phenomenon" => "novelty",
              "nats" => 3.0,
              "sources" => ["log.novelty", "log.template_share", "error.novelty"]
            },
            %{"phenomenon" => "request_errors", "nats" => 1.0, "sources" => ["error.negative_binomial"]}
          ],
          "evidence" => %{},
          "suspected_change" => nil
        })
      ])

    {:ok, view, _} = live(ctx.conn, "/#{ctx.account.name}/pulse/symptoms/#{id(1)}")

    assert has_element?(view, "#pulse-symptom-summary #pulse-symptom-sources")
    assert has_element?(view, "#pulse-symptom-sources .noora-badge", "Logs")
    assert has_element?(view, "#pulse-symptom-sources .noora-badge", "Errors")

    assert view
           |> element("#pulse-symptom-sources")
           |> render()
           |> Floki.parse_fragment!()
           |> Floki.find(".noora-badge")
           |> length() == 2

    refute has_element?(view, "#pulse-symptom-phenomena")
    refute has_element?(view, "#pulse-symptom-summary", "What changed")
    refute has_element?(view, "#pulse-symptom-technical")
    refute has_element?(view, "#pulse-symptom-brief")
    refute has_element?(view, "#pulse-symptom-create-brief")
    refute has_element?(view, "#pulse-symptom-change")
    refute has_element?(view, "#pulse-symptom-evidence")
    refute has_element?(view, "#pulse-symptom-detection-table")
    refute has_element?(view, "#pulse-symptom-mute-novelty")
    refute has_element?(view, "#pulse-symptom-measurements")
    refute has_element?(view, "#pulse-symptom-change")
    refute has_element?(view, "#pulse-symptom-evidence")
    refute has_element?(view, "#pulse-symptom-brief")
    render_patch(view, "/#{ctx.account.name}/pulse/symptoms/#{id(1)}?tab=invalid")
    refute has_element?(view, "#pulse-symptom-tabs")
    assert has_element?(view, "#pulse-symptom-history")
    assert has_element?(view, "#pulse-symptom-sources")
  end

  test "charts actual issue counts in the symptom environment and preserves the page on query failure", ctx do
    fingerprint = String.duplicate("a", 64)
    at = "2026-11-23T22:10:00Z"
    point = DateTime.to_unix(~U[2026-11-23 21:41:00Z])

    {:ok, _} =
      PulseFixtures.mirror_symptoms(ctx.account, [
        revision(1, %{
          "entity" => %{
            "kind" => "error_issue",
            "key" => fingerprint,
            "service" => "server",
            "environment" => "production"
          },
          "updated_at" => at
        })
      ])

    expect(Tuist.Pulse, :error_issue, fn user, account, ^fingerprint, params ->
      assert user.id == ctx.user.id
      assert account.id == ctx.account.id
      assert params == %{"service" => "server", "environment" => "production", "range" => "1h", "end_at" => at}
      {:ok, %{occurrence_series: [[point, 743], [point + 60, 0]]}}
    end)

    {:ok, view, _} = live(ctx.conn, "/#{ctx.account.name}/pulse/symptoms/#{id(1)}")
    render_async(view, 5_000)
    chart = view |> element("#pulse-symptom-occurrences [data-part='data']") |> render() |> Floki.parse_fragment!()
    [series] = chart |> Floki.text() |> JSON.decode!() |> Access.get("series")
    assert series["data"] == [[point * 1000, 743], [(point + 60) * 1000, 0]]
    refute has_element?(view, "#pulse-symptom-measurements", "No detector baseline")
    refute has_element?(view, "#pulse-symptom-measurements", "Recorded events in one-minute buckets")

    expect(Tuist.Pulse, :error_issue, fn _, _, _, _ -> {:error, :timeout} end)
    render_patch(view, "/#{ctx.account.name}/pulse/symptoms/#{id(1)}")
    render_async(view, 5_000)
    assert has_element?(view, "#pulse-symptom-measurements-unavailable", "Missing data is not zero events")
    refute has_element?(view, "#pulse-symptom-occurrences")
    assert has_element?(view, "#pulse-symptom-summary")
    assert has_element?(view, "#pulse-symptom-history")
  end

  test "shows labelled metadata and mutes without manual acknowledgement", ctx do
    {:ok, _} = PulseFixtures.mirror_symptoms(ctx.account, [revision(1, %{})])
    {:ok, view, _} = live(ctx.conn, "/#{ctx.account.name}/pulse/symptoms/#{id(1)}")

    refute has_element?(view, "#pulse-symptom-ack")
    refute has_element?(view, "#pulse-symptom-detail > [data-part=header] [data-part=badges]")
    assert has_element?(view, "#pulse-symptom-summary dt", "Severity")
    assert has_element?(view, "#pulse-symptom-summary dt", "State")
    assert has_element?(view, "#pulse-symptom-summary dt", "Service")
    refute has_element?(view, "#pulse-symptom-summary dt", "Entity")

    render_click(view, "mute", %{"phenomenon" => "latency", "duration" => "24h"})
    assert %SymptomMute{phenomenon: "latency", expires_at: expires_at} = Repo.one!(SymptomMute)
    assert_in_delta DateTime.diff(expires_at, DateTime.utc_now()), 86_400, 5
    assert has_element?(view, "#pulse-symptom-summary", "Muted until")
    refute has_element?(view, "#pulse-symptom-mute-latency")
  end

  test "offers muting only for the symptom's own phenomenon", ctx do
    {:ok, _} = PulseFixtures.mirror_symptoms(ctx.account, [revision(1, %{"phenomenon" => "latency"})])
    {:ok, view, _} = live(ctx.conn, "/#{ctx.account.name}/pulse/symptoms/#{id(1)}")

    refute has_element?(view, "#pulse-symptom-summary", "Request errors")
    assert has_element?(view, "#pulse-symptom-mute-latency")
    refute has_element?(view, "#pulse-symptom-mute-request_errors")
  end

  test "marks the confirmed outcome as selected", ctx do
    {:ok, _} = PulseFixtures.mirror_symptoms(ctx.account, [revision(1, %{"tier" => "page"})])
    {:ok, view, _} = live(ctx.conn, "/#{ctx.account.name}/pulse/symptoms/#{id(1)}")
    refute selected?(view, "pulse-symptom-outcome", "pulse-symptom-outcome-bad")

    render_click(view, "confirm_outcome", %{"outcome" => "bad"})
    assert selected?(view, "pulse-symptom-outcome", "pulse-symptom-outcome-bad")
    refute selected?(view, "pulse-symptom-outcome", "pulse-symptom-outcome-fine")
  end

  # Dropdown items render in a portal template, which selectors don't reach.
  defp selected?(view, dropdown, item) do
    html = view |> element("##{dropdown}-content-portal") |> render()
    html =~ ~r/<span[^>]* id="#{item}"[^>]* data-selected/
  end

  test "confirms the outcome from the detail page", ctx do
    {:ok, _} = PulseFixtures.mirror_symptoms(ctx.account, [revision(1, %{})])
    {:ok, view, _} = live(ctx.conn, "/#{ctx.account.name}/pulse/symptoms/#{id(1)}")
    assert has_element?(view, "#pulse-symptom-outcome")
    assert has_element?(view, "[data-part='actions']", "Was this a real problem?")

    render_click(view, "confirm_outcome", %{"outcome" => "bad"})
    assert %SymptomOutcome{outcome: :bad} = Repo.get_by!(SymptomOutcome, symptom_id: id(1))
    assert has_element?(view, "#pulse-symptom-summary", "Real problem")

    render_click(view, "confirm_outcome", %{"outcome" => "fine"})
    assert %SymptomOutcome{outcome: :fine} = Repo.get_by!(SymptomOutcome, symptom_id: id(1))
    assert has_element?(view, "#pulse-symptom-summary", "Not a problem")
  end

  test "investigation requests do not add brief controls to the symptom dashboard", ctx do
    {:ok, _} = PulseFixtures.mirror_symptoms(ctx.account, [revision(1, %{"tier" => "page"})])
    assert %Investigation{trigger: :brief} = Repo.one!(Investigation)
    {:ok, view, _} = live(ctx.conn, "/#{ctx.account.name}/pulse/symptoms/#{id(1)}")

    refute has_element?(view, "#pulse-symptom-brief")
    refute has_element?(view, "[phx-click='step_status']")
    refute has_element?(view, "#pulse-symptom-create-brief")
    assert Repo.aggregate(Investigation, :count) == 1
  end

  test "pages and actions are not found outside the Pulse account", ctx do
    {:ok, _} = PulseFixtures.mirror_symptoms(ctx.account, [revision(1, %{})])
    outsider = log_in_user(build_conn(), AccountsFixtures.user_fixture())

    assert_raise NotFoundError, fn -> live(outsider, "/#{ctx.account.name}/pulse") end
    assert_raise NotFoundError, fn -> live(outsider, "/#{ctx.account.name}/pulse/symptoms/#{id(1)}") end
    assert_raise NotFoundError, fn -> live(ctx.conn, "/#{ctx.account.name}/pulse/symptoms/#{id(9)}") end

    # Access removed while the page is open stops actions.
    {:ok, view, _} = live(ctx.conn, "/#{ctx.account.name}/pulse/symptoms/#{id(1)}")
    stub(Tuist.FeatureFlags, :pulse_enabled?, fn _ -> false end)
    Process.flag(:trap_exit, true)
    assert {{%NotFoundError{}, _}, _} = catch_exit(render_click(view, "confirm_outcome", %{"outcome" => "bad"}))
    assert Repo.aggregate(SymptomOutcome, :count) == 0
  end
end
