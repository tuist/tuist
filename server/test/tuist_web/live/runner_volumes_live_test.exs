defmodule TuistWeb.RunnerVolumesLiveTest do
  use ExUnit.Case, async: true
  use Mimic

  import Phoenix.LiveViewTest

  alias Phoenix.LiveView.AsyncResult
  alias Phoenix.LiveView.Socket
  alias Tuist.Authorization
  alias Tuist.Runners.CacheVolumes
  alias Tuist.Runners.CacheVolumes.Usage
  alias Tuist.Runners.CacheVolumes.Volume
  alias TuistWeb.RunnerVolumesLive

  defp assigns(can_manage) do
    volume = %Volume{id: Ecto.UUID.generate(), key: "gradle", repository: "org/repo", architecture: "amd64", uid: 1001}

    data = %{
      volumes: [volume],
      stats: %{
        volume.id => %{
          uses: 4,
          hits: 3,
          active: 0,
          retained_bytes: 1024,
          attach_ms: Decimal.new(12),
          retained_copies: 1
        }
      },
      storage_summary: %{
        volumes: 2,
        retained_copies: 3,
        retained_bytes: 1024,
        retained_capacity_bytes: 4096,
        unmeasured_copies: 1,
        unmeasured_capacity_copies: 0
      },
      more?: false,
      storage_history: [],
      previous_activity: %{hit_rate: 50.0},
      activity: %{uses: 4, hit_rate: 75.0, points: [%{at: ~U[2026-09-22 10:00:00Z], uses: 4, hit_rate: 75.0}]},
      analytics: %{
        storage: [%{at: ~U[2026-09-22 10:00:00Z], used_bytes: 1024, capacity_bytes: 4096}],
        activity: %{uses: 4, hit_rate: 75.0, points: [%{at: ~U[2026-09-22 10:00:00Z], uses: 4, hit_rate: 75.0}]}
      },
      history: []
    }

    %{
      selected_account: %{id: 1, name: "org"},
      selected: volume,
      selected_tab: "overview",
      storage_metric: "used_bytes",
      detail_metric: "used_bytes",
      analytics_preset: "last-7-days",
      analytics_period: {~U[2026-09-15 10:00:00Z], ~U[2026-09-22 10:00:00Z]},
      params: %{},
      search: "",
      sort_by: "last_used",
      sort_order: "desc",
      page: 1,
      data: AsyncResult.ok(data),
      pending_action: nil,
      can_manage: can_manage
    }
  end

  test "overview shows range-aware analytics and recent jobs without the full history" do
    html = render_component(&RunnerVolumesLive.render/1, assigns(true))
    assert html =~ "75.0%"
    assert html =~ "Job runs"
    assert html =~ "Number of job runs that mounted this volume during the selected period."
    refute html =~ "Branch protection"
    refute html =~ "request_policy"
    assert html =~ "Volume details"
    assert html =~ ~s(id="volume-capacity" data-part="metadata")
    refute html =~ ~s(phx-value-widget="capacity_bytes")
    refute html =~ "Automatically evicted after 7 days without a job mount"
    assert html =~ "volume-analytics-date-range-picker"
    assert html =~ "volume-analytics-chart"
    assert html =~ "Recent jobs"
    assert html =~ "View more"
    assert html =~ ~s(id="volume-recent-jobs")
    assert html =~ "tab=jobs"
    refute html =~ ~s(id="volumes-table")
    refute html =~ ~s(id="volume-history")
    refute html =~ ~s(id="volume-size-history")
    refute html =~ "Size history"
    refute html =~ "Last reported"
    refute html =~ "Average attach · 30 days"
    assert html =~ "not unique physical bytes"
    assert html =~ "request_delete"
  end

  test "account overview shows storage totals with missing measurement coverage" do
    html = render_component(&RunnerVolumesLive.render/1, %{assigns(true) | selected: nil})
    refute html =~ "7-day inactivity eviction"
    refute html =~ "storage-copies"
    refute html =~ "Last 7 days · hourly"
    refute html =~ "Unmeasured copies are excluded from reported storage."
    assert html =~ "since last period"
    assert html =~ "volumes-analytics-date-range-picker"
    refute html =~ "since first record"
    assert html =~ "Total used space"
    refute html =~ "Total capacity"
    assert html =~ "Cache hit rate"
    assert html =~ "75.0%"
    assert RunnerVolumesLive.storage_description(%{unmeasured_copies: 1}, :unmeasured_copies) =~ "1 copy unmeasured"
    assert html =~ "including copies awaiting deletion"
  end

  test "storage chart uses measurement values with gaps and inventory omits status" do
    assigns = assigns(true)

    data = %{
      assigns.data.result
      | storage_history: [
          %{at: ~U[2026-09-22 10:00:00Z], used_bytes: nil, capacity_bytes: 4096, volumes: 1},
          %{at: ~U[2026-09-22 11:00:00Z], used_bytes: 1024, capacity_bytes: 4096, volumes: 2}
        ]
    }

    html = render_component(&RunnerVolumesLive.render/1, %{assigns | selected: nil, data: AsyncResult.ok(data)})
    assert html =~ "volume-storage-chart"
    refute html =~ "Reported storage"
    refute html =~ ">Status<"
    assert html =~ "No change"
    [volumes, used, capacity] = RunnerVolumesLive.storage_chart_series(data.storage_history)
    assert List.last(volumes.data) == ["2026-09-22T11:00:00Z", 2]
    refute Map.has_key?(used, :step)
    assert used.data == [["2026-09-22T10:00:00Z", nil], ["2026-09-22T11:00:00Z", 1024]]
    assert capacity.data == [["2026-09-22T10:00:00Z", 4096], ["2026-09-22T11:00:00Z", 4096]]
    refute used.connectNulls
    socket = %Socket{assigns: %{__changed__: %{}, storage_metric: "used_bytes"}}

    assert {:noreply, updated} =
             RunnerVolumesLive.handle_event("select_storage_metric", %{"widget" => "hit_rate"}, socket)

    assert updated.assigns.storage_metric == "hit_rate"
    assert {:noreply, updated} = RunnerVolumesLive.handle_event("select_storage_metric", %{"widget" => "volumes"}, socket)
    assert updated.assigns.storage_metric == "volumes"
    assert RunnerVolumesLive.storage_chart_options("volumes").yAxis.axisLabel.formatter == "fn:formatNumber"
    assert RunnerVolumesLive.storage_chart_options("used_bytes").yAxis.axisLabel.formatter == "fn:formatBytes"
  end

  test "hit rate trends use percentage points and distinguish unavailable comparisons" do
    assert %{value: 25.0, value_label: "+25.0 pp"} = RunnerVolumesLive.hit_rate_trend(75.0, 50.0)
    assert %{value: -25.0, value_label: "-25.0 pp"} = RunnerVolumesLive.hit_rate_trend(50.0, 75.0)
    assert %{value: 50.0, value_label: "+50.0 pp"} = RunnerVolumesLive.hit_rate_trend(50.0, 0.0)
    assert %{value: unchanged_rate, value_label: nil} = RunnerVolumesLive.hit_rate_trend(50.0, 50.0)
    assert unchanged_rate == 0.0
    assert %{value: 0, value_label: "No previous data"} = RunnerVolumesLive.hit_rate_trend(75.0, nil)
    assert %{value: 0, value_label: "No data"} = RunnerVolumesLive.hit_rate_trend(nil, 75.0)
    period = {~U[2026-09-15 10:00:00Z], ~U[2026-09-22 10:00:00Z]}
    assert RunnerVolumesLive.previous_period(period) == {~U[2026-09-08 10:00:00.000000Z], ~U[2026-09-15 09:59:59.999999Z]}
    html = render_component(&RunnerVolumesLive.render/1, %{assigns(true) | selected: nil})
    assert html =~ "+25.0 pp"
  end

  test "inventory hit rate charts work without storage measurements and preserve unknown results" do
    assigns = %{assigns(true) | selected: nil, storage_metric: "hit_rate"}
    data = assigns.data.result
    html = render_component(&RunnerVolumesLive.render/1, assigns)
    assert html =~ "volume-storage-chart"
    assert html =~ "Percentage of volume mounts that reused saved data during the selected period."
    assert [%{type: "line", data: [[_, 75.0]]}] = RunnerVolumesLive.inventory_chart_series(data, "hit_rate")
    options = RunnerVolumesLive.detail_chart_options("hit_rate", assigns.analytics_period)
    assert options.yAxis.min == 0
    assert options.yAxis.max == 100
    assert options.tooltip.valueFormat == "{value}%"

    data = %{data | activity: %{data.activity | hit_rate: nil}}
    html = render_component(&RunnerVolumesLive.render/1, %{assigns | data: AsyncResult.ok(data)})
    refute html =~ "volume-storage-chart"
    assert html =~ "No data in this period"
    refute RunnerVolumesLive.inventory_chart_data?(data, "hit_rate")
    assert RunnerVolumesLive.inventory_chart_data?(%{data | activity: %{data.activity | hit_rate: 0.0}}, "hit_rate")
  end

  test "sorting resets pagination and preserves search and analytics range" do
    assigns = %{
      assigns(true)
      | selected: nil,
        page: 3,
        params: %{"page" => "3", "search" => "gradle", "analytics-date-range" => "last-30-days"}
    }

    url = RunnerVolumesLive.sort_patch(assigns, "volume")
    params = url |> URI.parse() |> Map.fetch!(:query) |> URI.decode_query()

    assert params == %{
             "search" => "gradle",
             "analytics-date-range" => "last-30-days",
             "sort_by" => "volume",
             "sort_order" => "asc"
           }

    assert RunnerVolumesLive.sort_patch(%{assigns | sort_by: "volume", sort_order: "asc"}, "volume") =~ "sort_order=desc"
    assert RunnerVolumesLive.sort_patch(assigns, "used_space") =~ "sort_order=desc"

    data = %{assigns.data.result | more?: true}
    html = render_component(&RunnerVolumesLive.render/1, %{assigns | data: AsyncResult.ok(data)})
    assert html =~ "volumes-sort-by-dropdown"
    assert html =~ "Prev"
    assert html =~ "Next"
    assert html =~ "page=4"
  end

  test "storage trends use the Jobs zero fallback when the previous period is unavailable" do
    points = [
      %{at: ~U[2026-09-15 10:00:00Z], volumes: 2, used_bytes: 1024},
      %{at: ~U[2026-09-22 10:00:00Z], volumes: 3, used_bytes: 512}
    ]

    period = {hd(points).at, List.last(points).at}
    assert %{value: 50.0, label: "since last period"} = RunnerVolumesLive.storage_trend(points, :volumes, period)
    assert %{value: -50.0} = RunnerVolumesLive.storage_trend(points, :used_bytes, period)
    short = put_in(points, [Access.at(0), :at], ~U[2026-09-22 09:00:00Z])

    assert %{value: 0, value_label: nil, label: "since last period"} =
             RunnerVolumesLive.storage_trend(short, :volumes, period)

    zero = put_in(points, [Access.at(0), :volumes], 0)
    assert %{value_label: "+3"} = RunnerVolumesLive.storage_trend(zero, :volumes, period)
    unknown = Enum.map(points, &Map.put(&1, :used_bytes, nil))

    assert %{value: 0, value_label: nil, label: "since last period"} =
             RunnerVolumesLive.storage_trend(unknown, :used_bytes, period)
  end

  test "storage ranges default to a week and support presets and bounded custom periods" do
    assert %{preset: "last-7-days", period: {start, finish}} = RunnerVolumesLive.storage_period(%{})
    assert DateTime.diff(finish, start) == 7 * 86_400

    for {preset, days} <- [{"last-24-hours", 1}, {"last-30-days", 30}] do
      assert %{preset: ^preset, period: {start, finish}} =
               RunnerVolumesLive.storage_period(%{"analytics-date-range" => preset})

      assert DateTime.diff(finish, start) == days * 86_400
    end

    finish = DateTime.utc_now() |> DateTime.truncate(:second) |> DateTime.add(-2, :day)
    start = DateTime.add(finish, -3, :day)

    params = %{
      "analytics-date-range" => "custom",
      "analytics-start-date" => DateTime.to_iso8601(start),
      "analytics-end-date" => DateTime.to_iso8601(finish)
    }

    assert %{preset: "custom", period: {^start, ^finish}} = RunnerVolumesLive.storage_period(params)

    assert %{preset: "last-7-days"} =
             RunnerVolumesLive.storage_period(Map.put(params, "analytics-start-date", "2000-01-01T00:00:00Z"))

    assert %{preset: "last-7-days"} =
             RunnerVolumesLive.storage_period(
               Map.put(params, "analytics-start-date", DateTime.to_iso8601(DateTime.add(finish, 1, :day)))
             )
  end

  test "historical widget values use the selected period endpoint" do
    points = [%{at: ~U[2026-09-22 10:00:00Z], volumes: 2, used_bytes: nil, capacity_bytes: 4096}]
    assert RunnerVolumesLive.storage_value(points, :volumes) == "2"
    assert RunnerVolumesLive.storage_value(points, :used_bytes) == "—"
    assert RunnerVolumesLive.storage_value(points, :capacity_bytes) == RunnerVolumesLive.bytes(4096)
    assert RunnerVolumesLive.storage_value([], :volumes) == "—"
  end

  test "date range changes retain search and metric selection" do
    socket = %Socket{
      assigns: %{
        __changed__: %{},
        selected_account: %{name: "org"},
        storage_metric: "used_bytes",
        params: %{"search" => "gradle", "analytics-start-date" => "old"}
      }
    }

    event = %{"value" => %{"start" => "2026-09-10T00:00:00Z", "end" => "2026-09-12T00:00:00Z"}, "preset" => "custom"}
    assert {:noreply, updated} = RunnerVolumesLive.handle_event("analytics_period_changed", event, socket)
    params = updated.redirected |> elem(2) |> Map.fetch!(:to) |> URI.parse() |> Map.fetch!(:query) |> URI.decode_query()
    assert params["search"] == "gradle"
    assert params["analytics-start-date"] == event["value"]["start"]
    assert params["analytics-end-date"] == event["value"]["end"]
    assert updated.assigns.storage_metric == "used_bytes"

    assert {:noreply, updated} =
             RunnerVolumesLive.handle_event("analytics_period_changed", %{event | "preset" => "last-30-days"}, socket)

    refute elem(updated.redirected, 2).to =~ "analytics-start-date"
  end

  test "detail charts switch between byte, percentage and mount count series" do
    analytics = assigns(true).data.result.analytics
    period = assigns(true).analytics_period
    assert [%{type: "line", data: [[_, 1024]]}] = RunnerVolumesLive.detail_chart_series(analytics, "used_bytes")
    assert [%{type: "line", data: [[_, 75.0]]}] = RunnerVolumesLive.detail_chart_series(analytics, "hit_rate")
    assert [%{type: "bar", data: [[_, 4]]}] = RunnerVolumesLive.detail_chart_series(analytics, "uses")
    assert RunnerVolumesLive.detail_chart_options("hit_rate", period).yAxis.max == 100
    assert RunnerVolumesLive.detail_chart_options("hit_rate", period).tooltip.valueFormat == "{value}%"
    assert RunnerVolumesLive.detail_chart_options("uses", period).yAxis.axisLabel.formatter == "fn:formatNumber"
    empty = %{analytics | activity: %{analytics.activity | hit_rate: nil}}
    refute RunnerVolumesLive.detail_chart_data?(empty, "hit_rate")

    socket = %Socket{assigns: %{__changed__: %{}, detail_metric: "used_bytes"}}

    for metric <- ["used_bytes", "hit_rate", "uses"] do
      assert {:noreply, updated} = RunnerVolumesLive.handle_event("select_detail_metric", %{"widget" => metric}, socket)
      assert updated.assigns.detail_metric == metric
    end
  end

  test "detail range changes stay on the volume and tab navigation preserves the range" do
    volume = assigns(true).selected
    params = %{"tab" => "overview", "analytics-date-range" => "last-24-hours", "page" => "2"}
    socket = %Socket{assigns: %{__changed__: %{}, selected_account: %{name: "org"}, selected: volume, params: params}}
    event = %{"value" => %{"start" => "2026-09-10T00:00:00Z", "end" => "2026-09-12T00:00:00Z"}, "preset" => "custom"}
    assert {:noreply, updated} = RunnerVolumesLive.handle_event("analytics_period_changed", event, socket)
    assert elem(updated.redirected, 2).to =~ "/runners/volumes/#{volume.id}?"
    assert elem(updated.redirected, 2).to =~ "analytics-date-range=custom"
    assert RunnerVolumesLive.tab_params(params, "jobs") == %{"tab" => "jobs", "analytics-date-range" => "last-24-hours"}
  end

  test "empty storage is zero but an unmeasured copy remains unknown" do
    assert RunnerVolumesLive.storage_bytes(%{retained_copies: 0, retained_bytes: nil}, :retained_bytes) ==
             RunnerVolumesLive.bytes(0)

    assert RunnerVolumesLive.storage_bytes(%{retained_copies: 1, retained_bytes: nil}, :retained_bytes) == "—"
    empty = %Volume{head_id: nil, deleted_at: nil}
    unknown = %{retained_copies: 1, retained_bytes: nil}
    assert RunnerVolumesLive.used_space(empty, unknown) == "0 B"
    assert RunnerVolumesLive.used_space(empty, %{}) == "0 B"
    assert RunnerVolumesLive.used_space(empty, %{unknown | retained_bytes: 1024}) == "1.0 KB"
    assert RunnerVolumesLive.used_space(%{empty | head_id: Ecto.UUID.generate()}, unknown) == "—"
    assert RunnerVolumesLive.used_space(%{empty | deleted_at: ~U[2026-09-22 10:00:00Z]}, unknown) == "—"
  end

  test "jobs render separately and removed tabs fall back to overview" do
    assigns = assigns(true)

    usage = %Usage{
      id: Ecto.UUID.generate(),
      workflow_job_id: 1024,
      workflow_run_id: 1000,
      job_name: "Build and test",
      workflow_name: "Continuous integration",
      status: "published",
      warm: true
    }

    data = %{assigns.data.result | history: [usage]}
    jobs = render_component(&RunnerVolumesLive.render/1, %{assigns | selected_tab: "jobs", data: AsyncResult.ok(data)})
    assert jobs =~ "Build and test"
    assert jobs =~ "Workflow"
    assert jobs =~ "Continuous integration"
    assert RunnerVolumesLive.workflow_label(%{usage | workflow_name: nil}) == "Unknown"
    assert RunnerVolumesLive.workflow_label(%{usage | workflow_name: ""}) == "Unknown"
    assert jobs =~ "Cache status"
    assert jobs =~ "Saved"
    assert jobs =~ "Changes from this job were saved to the volume for future job runs."
    assert jobs =~ ~s(id="volume-use-status-#{usage.id}")
    assert jobs =~ ~s(data-type="status_badge")
    refute jobs =~ "Published"
    assert RunnerVolumesLive.job_label(%{usage | job_name: nil}) == "# 1024"
    assert RunnerVolumesLive.job_label(%{usage | job_name: ""}) == "# 1024"
    assert jobs =~ ~s(id="volume-history")
    refute jobs =~ ~s(id="volume-size-history")
    assert jobs =~ "Volume details"
    assert :binary.match(jobs, "Volume details") < :binary.match(jobs, "noora-tab-menu-horizontal")
    assert RunnerVolumesLive.selected_tab("size-history") == "overview"
    assert RunnerVolumesLive.selected_tab("invalid") == "overview"
  end

  test "reader sees metrics but no mutation controls" do
    html = render_component(&RunnerVolumesLive.render/1, assigns(false))
    assert html =~ "Hit rate"
    refute html =~ "request_delete"
    refute html =~ "request_policy"
  end

  test "pending deletion is based on retained copies even before size is known" do
    volume = %Volume{deleted_at: ~U[2026-09-17 12:00:00Z]}
    assert RunnerVolumesLive.status(volume, %{retained_copies: 1, retained_bytes: nil}) == "Deletion pending"
    assert RunnerVolumesLive.status(volume, %{retained_copies: 0}) == "Deleted"
  end

  test "confirmation rechecks authorization rather than trusting a stale admin assign" do
    expect(Authorization, :authorize, fn :account_update, :user, %{id: 1} -> {:error, :unauthorized} end)

    socket = %Socket{
      assigns: %{
        __changed__: %{},
        selected_account: %{id: 1},
        current_user: :user,
        can_manage: true,
        pending_action: {:delete, Ecto.UUID.generate()}
      }
    }

    assert {:noreply, ^socket} = RunnerVolumesLive.handle_event("confirm", %{}, socket)
  end

  test "requesting another account's volume never opens confirmation" do
    id = Ecto.UUID.generate()
    expect(CacheVolumes, :get, fn 1, ^id -> nil end)
    socket = %Socket{assigns: %{__changed__: %{}, selected_account: %{id: 1}, can_manage: true}}
    assert {:noreply, ^socket} = RunnerVolumesLive.handle_event("request_delete", %{"id" => id}, socket)
  end
end
