Code.require_file("source_helpers.ex", __DIR__)

defmodule Symptoms.Sources.PulseLogsTest do
  use ExUnit.Case, async: true
  use Mimic

  import Symptoms.SourceHelpers

  alias Symptoms.Sources.PulseLogs

  @moduletag :capture_log

  @start 1_763_301_600
  @window %{start: @start, seconds: 60}
  @service "tuist-server"

  defp entity(key), do: %{environment: "production", service: @service, kind: "log_template", key: key}

  defp count(key, level, lines),
    do: %{"service" => @service, "level" => level, "template_key" => key, "line_count" => lines}

  defp sighting(key, lines, windows, first_seen \\ @start - 600),
    do: %{
      "service" => @service,
      "template_key" => key,
      "line_count" => lines,
      "windows" => windows,
      "first_seen" => first_seen
    }

  defp stub(counts, sightings) do
    stub_pulse(fn sql ->
      cond do
        sql =~ "AS latest FROM" -> latest(@start + 60)
        sql =~ "count(DISTINCT time_window)" -> sightings
        sql =~ "FROM symptoms_log_counts_1m" -> counts
        sql =~ "FROM symptoms_log_totals_1m" -> [%{"service" => @service, "line_count" => 1000}]
      end
    end)
  end

  defp known(keys), do: fn entity -> entity.key in keys end

  test "template share against the service total" do
    stub([count("k1", "info", 30)], [])
    opts = pulse_opts(known?: known(["k1"]), baseline: baselines(%{{"log.template_share", "k1"} => %{p: 0.01, rho: 0.0}}))

    assert {:ok, [record]} = PulseLogs.collect(@window, opts)
    # (30 - 1000 · 0.01) / sqrt(1000 · 0.01 · 0.99) = 20 / sqrt(9.9)
    assert record.entity == entity("k1")
    assert record.phenomenon == :platform_events
    assert_in_delta record.statistic, 20 / :math.sqrt(9.9), 1.0e-9
    assert record.n == 1000
  end

  test "an error-level template is request errors" do
    stub([count("k1", "info", 10), count("k1", "ERROR", 20)], [])
    opts = pulse_opts(known?: known(["k1"]), baseline: baselines(%{{"log.template_share", "k1"} => %{p: 0.01, rho: 0.0}}))

    assert {:ok, [%{phenomenon: :request_errors, observed: 0.03}]} = PulseLogs.collect(@window, opts)
  end

  test "vanished templates count only when 20 or more were expected and no deploy removed them" do
    stub([], [])

    opts =
      pulse_opts(
        known?: known(["k2", "k3", "k4"]),
        entities: [entity("k2"), entity("k3"), entity("k4")],
        removed_by_deploy?: &(&1.key == "k4"),
        baseline:
          baselines(%{
            {"log.template_share", "k2"} => %{p: 0.05, rho: 0.0},
            {"log.template_share", "k3"} => %{p: 0.01, rho: 0.0},
            {"log.template_share", "k4"} => %{p: 0.05, rho: 0.0}
          })
      )

    # k2 expects 50 lines: |0 - 50| / sqrt(1000 · 0.05 · 0.95) = 50 / sqrt(47.5).
    # k3 expects 10 (< 20); k4 was removed by a deploy.
    assert {:ok, [record]} = PulseLogs.collect(@window, opts)
    assert record.entity == entity("k2")
    assert record.source == "log.template_vanished"
    assert_in_delta record.statistic, 50 / :math.sqrt(47.5), 1.0e-9
  end

  test "vanished templates require removal metadata even after the recent-deploy window expires" do
    stub([], [])
    deploy = %{kind: :deploy, service: @service, at: @start - 600, ref: "1.5.0"}

    opts =
      pulse_opts(entities: [entity("k1")], baseline: baselines(%{{"log.template_share", "k1"} => %{p: 0.05, rho: 0.0}}))

    assert {:ok, []} = PulseLogs.collect(@window, Keyword.put(opts, :deploys, [deploy]))

    for changes <- [
          [],
          [%{deploy | service: "kura"}],
          [%{deploy | at: @start - 1800}],
          [%{deploy | at: @start + 60}],
          [%{deploy | kind: :config}]
        ] do
      assert {:ok, []} = PulseLogs.collect(@window, Keyword.put(opts, :deploys, changes))
    end

    # An authoritative lookup enables detection only for code known to remain.
    opts = Keyword.put(opts, :deploys, [deploy])

    assert {:ok, [%{source: "log.template_vanished"}]} =
             PulseLogs.collect(@window, Keyword.put(opts, :removed_by_deploy?, fn _ -> false end))

    assert {:ok, []} = PulseLogs.collect(@window, Keyword.put(opts, :removed_by_deploy?, fn _ -> true end))
  end

  test "a key is new after 3 sightings in 2 windows, once" do
    stub(
      [count("n1", "warning", 2), count("n2", "warning", 1), count("n3", "warning", 1)],
      # n1: 3 lines in 2 minutes now, 1 in 1 before → new now.
      # n2: 5 in 3 now, 4 in 2 before → already new. n3: 2 lines → not yet.
      [sighting("n1", 3, 2), sighting("n2", 5, 3), sighting("n3", 2, 2)]
    )

    assert {:ok, [record]} = PulseLogs.collect(@window, pulse_opts())
    assert record.entity == entity("n1")
    assert record.phenomenon == :novelty
    assert record.statistic == 3.0
  end

  test "deploy-introduced keys count as novelty only when error-level" do
    stub(
      [count("d1", "info", 2), count("d2", "error", 2)],
      [sighting("d1", 3, 2, @start - 300), sighting("d2", 3, 2, @start - 300)]
    )

    deploy = %{kind: :deploy, service: @service, at: @start - 600, ref: "1.5.0"}
    assert {:ok, [record]} = PulseLogs.collect(@window, pulse_opts(deploys: [deploy]))
    assert record.entity == entity("d2")

    # Another service's deploy does not exempt it.
    other = %{deploy | service: "kura"}
    assert {:ok, records} = PulseLogs.collect(@window, pulse_opts(deploys: [other]))
    assert records |> Enum.map(& &1.entity.key) |> Enum.sort() == ["d1", "d2"]
  end

  test "too many new keys disable novelty for the service and report it" do
    stub([count("a", "info", 2), count("b", "info", 2), count("c", "info", 2)], [sighting("a", 3, 2)])
    test = self()

    assert {:ok, []} =
             PulseLogs.collect(@window, pulse_opts(novelty_cap: 2, novelty_disabled: &send(test, {:disabled, &1, &2})))

    assert_received {:disabled, @service, 3}
    # No sightings were read for the capped service.
    refute_received {:sql, "SELECT service, template_key, sum(line_count) AS line_count, count(DISTINCT" <> _, _}
  end

  test "a lagging totals flow is unknown" do
    stub_pulse(fn sql -> if sql =~ "AS latest FROM", do: latest(@start), else: flunk(sql) end)
    assert {:unknown, [_]} = PulseLogs.collect(@window, pulse_opts(entities: [entity("k1")]))
  end
end
