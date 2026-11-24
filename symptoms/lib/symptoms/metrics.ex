defmodule Symptoms.Metrics do
  @moduledoc """
  Coverage and heartbeat metrics in Prometheus text format (README
  "Backstops and watching the watcher"):

  - `symptoms_up`: 1 when the database answered, 0 otherwise.
  - `symptoms_entities_expected`: non-retired entities seen in the last 24
    hours. `symptoms_entities_with_evidence`: those with evidence in the last
    10 minutes. `symptoms_coverage_ratio`: their ratio (1 with none
    expected). `symptoms_entities_unknown`: entities marked unknown.
  - `symptoms_source_last_success_timestamp_seconds{source}` and
    `symptoms_source_freshness_seconds{source}`: when a source last
    collected, and how old the end of the last window it collected is.
  - `symptoms_sources_configured`: configured sources that are not
    disabled. With none, or with no entity expected, the coverage ratio
    reads 1 and nothing is watched; the `symptoms-nothing-watched` rule
    fires on either.
  - `symptoms_source_up{source}`: 0 for a configured source that is disabled
    or whose last collect failed. `symptoms_streams_disabled`: their count.
  - `symptoms_pipeline_last_success_timestamp_seconds{window_seconds}` and
    `symptoms_pipeline_lag_seconds{window_seconds}`: when the pipeline last
    finished a window, and how far the end of the latest finished window is
    behind now.
  - `symptoms_open_symptoms{tier}`.
  """

  import Ecto.Query

  alias Symptoms.Repo
  alias Symptoms.Store.Entity
  alias Symptoms.Store.PipelineRun
  alias Symptoms.Store.SourceStatus
  alias Symptoms.Store.Symptom

  @doc "The metrics text at `now`."
  @spec render(DateTime.t()) :: String.t()
  def render(now) do
    now |> collect() |> Enum.map_join(&line/1)
  rescue
    _ in [DBConnection.ConnectionError, Postgrex.Error] -> line({"symptoms_up", %{}, 0})
  end

  defp collect(now) do
    seen_after = DateTime.shift(now, day: -1)
    evidence_after = DateTime.shift(now, minute: -10)

    expected =
      Repo.aggregate(from(e in Entity, where: is_nil(e.retired_at) and e.last_seen_at >= ^seen_after), :count)

    with_evidence =
      Repo.aggregate(
        from(e in Entity,
          where: is_nil(e.retired_at) and e.last_seen_at >= ^seen_after and e.last_evidence_at >= ^evidence_after
        ),
        :count
      )

    unknown = Repo.aggregate(from(e in Entity, where: is_nil(e.retired_at) and e.unknown), :count)

    [
      {"symptoms_up", %{}, 1},
      {"symptoms_entities_expected", %{}, expected},
      {"symptoms_entities_with_evidence", %{}, with_evidence},
      {"symptoms_coverage_ratio", %{}, if(expected == 0, do: 1.0, else: with_evidence / expected)},
      {"symptoms_entities_unknown", %{}, unknown}
    ] ++ sources(now) ++ pipeline(now) ++ open_symptoms()
  end

  defp sources(now) do
    statuses = Map.new(Repo.all(SourceStatus), &{&1.source, &1})
    disabled = Application.get_env(:symptoms, :disabled_sources, [])

    configured =
      Enum.map(Application.get_env(:symptoms, :sources, []), fn module ->
        {module.name(), module in disabled}
      end)

    names = Enum.uniq(Enum.map(configured, &elem(&1, 0)) ++ Map.keys(statuses))
    disabled_names = for {name, true} <- configured, do: name

    per_source =
      Enum.flat_map(Enum.sort(names), fn name ->
        status = statuses[name]

        failing =
          status && status.last_error_at &&
            (is_nil(status.last_success_at) or DateTime.after?(status.last_error_at, status.last_success_at))

        up = if name in disabled_names or failing, do: 0, else: 1
        labels = %{"source" => name}

        [{"symptoms_source_up", labels, up}] ++
          if(status && status.last_success_at,
            do: [
              {"symptoms_source_last_success_timestamp_seconds", labels, DateTime.to_unix(status.last_success_at)},
              {"symptoms_source_freshness_seconds", labels, DateTime.diff(now, status.last_window_end)}
            ],
            else: []
          )
      end)

    down = Enum.count(per_source, &match?({"symptoms_source_up", _, 0}, &1))
    enabled = Enum.count(configured, fn {_name, disabled} -> not disabled end)
    [{"symptoms_sources_configured", %{}, enabled}, {"symptoms_streams_disabled", %{}, down} | per_source]
  end

  defp pipeline(now) do
    from(r in PipelineRun,
      group_by: r.window_seconds,
      select: {r.window_seconds, max(r.window_start), max(r.finished_at)}
    )
    |> Repo.all()
    |> Enum.flat_map(fn {window_seconds, window_start, finished_at} ->
      labels = %{"window_seconds" => Integer.to_string(window_seconds)}

      [
        {"symptoms_pipeline_last_success_timestamp_seconds", labels, DateTime.to_unix(finished_at)},
        {"symptoms_pipeline_lag_seconds", labels,
         DateTime.diff(now, DateTime.shift(window_start, second: window_seconds))}
      ]
    end)
  end

  defp open_symptoms do
    counts =
      Map.new(Repo.all(from(s in Symptom, where: s.state == "open", group_by: s.tier, select: {s.tier, count(s.id)})))

    for tier <- ~w(audit board page), do: {"symptoms_open_symptoms", %{"tier" => tier}, Map.get(counts, tier, 0)}
  end

  defp line({name, labels, value}) do
    label_text =
      if labels == %{},
        do: "",
        else: "{" <> Enum.map_join(Enum.sort(labels), ",", fn {k, v} -> ~s(#{k}="#{escape(v)}") end) <> "}"

    "#{name}#{label_text} #{value}\n"
  end

  defp escape(value),
    do: value |> String.replace("\\", "\\\\") |> String.replace("\"", "\\\"") |> String.replace("\n", "\\n")
end
