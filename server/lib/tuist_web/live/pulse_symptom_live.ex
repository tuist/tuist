defmodule TuistWeb.PulseSymptomLive do
  @moduledoc """
  One mirrored symptom: why it surfaced, its revision history, evidence
  references and masked excerpts, the suspected change and
  the outcome, with mute and detection feedback actions. Everything from the evaluator is
  untrusted text: it is rendered escaped and never linked.
  """
  use TuistWeb, :live_view
  use Noora

  import TuistWeb.Components.Skeleton

  alias Tuist.Pulse
  alias Tuist.Pulse.Symptoms
  alias Tuist.Utilities.DateFormatter
  alias TuistWeb.Errors.NotFoundError
  alias TuistWeb.PulseSymptomsLive

  @mute_durations %{"1h" => 3600, "24h" => 86_400, "7d" => 7 * 86_400}

  def mount(_params, _session, socket) do
    authorize!(socket)
    {:ok, socket}
  end

  def handle_params(%{"id" => id}, _uri, socket) do
    authorize!(socket)
    {:noreply, socket |> assign(id: id) |> load()}
  end

  def handle_event("mute", %{"phenomenon" => phenomenon, "duration" => duration}, socket) do
    authorize!(socket)

    case Map.fetch(@mute_durations, duration) do
      {:ok, seconds} ->
        socket.assigns.current_user
        |> Symptoms.mute(
          socket.assigns.selected_account,
          socket.assigns.id,
          phenomenon,
          DateTime.add(DateTime.utc_now(), seconds, :second)
        )
        |> after_action(socket, dgettext("dashboard_pulse", "Phenomenon muted on this entity."))

      :error ->
        after_action({:error, :invalid_params}, socket, nil)
    end
  end

  def handle_event("confirm_outcome", %{"outcome" => outcome}, socket) do
    authorize!(socket)

    socket.assigns.current_user
    |> Symptoms.confirm_outcome(socket.assigns.selected_account, socket.assigns.id, outcome)
    |> after_action(socket, dgettext("dashboard_pulse", "Detection feedback saved."))
  end

  defp after_action(:ok, socket, message), do: {:noreply, socket |> put_flash(:info, message) |> load()}

  defp after_action({:error, _reason}, socket, _message),
    do: {:noreply, put_flash(socket, :error, dgettext("dashboard_pulse", "The symptom could not be updated."))}

  defp authorize!(socket) do
    if !Pulse.authorized?(socket.assigns.current_user, socket.assigns.selected_account) do
      raise NotFoundError, "Not found"
    end
  end

  defp load(socket) do
    case Symptoms.get(socket.assigns.current_user, socket.assigns.selected_account, socket.assigns.id) do
      {:ok, detail} ->
        socket
        |> assign(:detail, detail)
        |> load_measurements(detail.symptom)
        |> assign(
          :head_title,
          "#{dgettext("dashboard_pulse", "Symptom")} · #{socket.assigns.selected_account.name} · Tuist"
        )

      {:error, _reason} ->
        raise NotFoundError, "Not found"
    end
  end

  # Reuse the authorized issue reader, scoped to the symptom's environment and
  # pinned to its last revision. These are measurements, not detector scores.
  defp load_measurements(socket, %{entity_kind: "error_issue"} = symptom) do
    user = socket.assigns.current_user
    account = socket.assigns.selected_account

    params = %{
      "service" => symptom.service,
      "environment" => symptom.environment,
      "range" => "1h",
      "end_at" => DateTime.to_iso8601(symptom.revised_at)
    }

    if connected?(socket) do
      socket
      |> cancel_async(:measurements)
      |> assign_async(
        :measurements,
        fn ->
          case Pulse.error_issue(user, account, symptom.entity_key, params) do
            {:ok, result} -> {:ok, %{measurements: result}}
            {:error, reason} -> {:error, reason}
          end
        end,
        reset: true
      )
    else
      assign(socket, :measurements, Phoenix.LiveView.AsyncResult.loading())
    end
  end

  defp load_measurements(socket, _symptom), do: socket |> cancel_async(:measurements) |> assign(:measurements, nil)

  def render(assigns) do
    assigns =
      assigns
      |> assign(:symptom, assigns.detail.symptom)
      |> assign(:evidence, assigns.detail.symptom.evidence || %{})
      |> assign(:source_badges, source_badges(assigns.detail.symptom.phenomena))
      |> assign(:mute_durations, [
        {"1h", dgettext("dashboard_pulse", "For 1 hour")},
        {"24h", dgettext("dashboard_pulse", "For 24 hours")},
        {"7d", dgettext("dashboard_pulse", "For 7 days")}
      ])

    ~H"""
    <div id="pulse-symptom-detail">
      <.button
        id="pulse-symptom-back"
        data-part="back-button"
        variant="secondary"
        size="medium"
        label="Pulse"
        navigate={~p"/#{@selected_account.name}/pulse"}
      >
        <:icon_left><.arrow_left /></:icon_left>
      </.button>
      <div data-part="header">
        <div data-part="title-group">
          <div data-part="title">
            <span data-part="state-icon" data-color={state_icon_color(@symptom)}>
              <.icon name={state_icon(@symptom.state)} />
            </span>
            <h1 data-part="detail-title">
              {@symptom.title || dgettext("dashboard_pulse", "Untitled symptom")}
            </h1>
          </div>
        </div>
        <div data-part="actions">
          <.dropdown
            :if={
              @detail.phenomenon && !Enum.any?(@detail.mutes, &(&1.phenomenon == @detail.phenomenon))
            }
            id={"pulse-symptom-mute-#{@detail.phenomenon}"}
            size="medium"
            label={
              dgettext("dashboard_pulse", "Mute %{phenomenon}",
                phenomenon: PulseSymptomsLive.phenomenon_label(@detail.phenomenon)
              )
            }
          >
            <.dropdown_item
              :for={{duration, label} <- @mute_durations}
              value={duration}
              label={label}
              on_click="mute"
              phx-value-phenomenon={@detail.phenomenon}
              phx-value-duration={duration}
            />
          </.dropdown>
          <.dropdown
            id="pulse-symptom-outcome"
            size="medium"
            label={outcome_label(@detail.outcome)}
          >
            <.dropdown_item
              :for={{value, label} <- outcome_options()}
              id={"pulse-symptom-outcome-#{value}"}
              value={value}
              label={label}
              on_click="confirm_outcome"
              phx-value-outcome={value}
              data-selected={!!@detail.outcome && Atom.to_string(@detail.outcome.outcome) == value}
            >
              <:right_icon><.check /></:right_icon>
            </.dropdown_item>
          </.dropdown>
        </div>
      </div>
      <.card
        id="pulse-symptom-summary"
        title={dgettext("dashboard_pulse", "Overview")}
        icon="alert_triangle"
      >
        <.card_section>
          <dl data-part="metadata-grid">
            <.field
              label={dgettext("dashboard_pulse", "Severity")}
              value={PulseSymptomsLive.tier_label(@symptom.tier)}
            />
            <.field
              label={dgettext("dashboard_pulse", "State")}
              value={PulseSymptomsLive.state_label(Atom.to_string(@symptom.state))}
            />
            <.field label={dgettext("dashboard_pulse", "Service")} value={@symptom.service} />
            <.field label={dgettext("dashboard_pulse", "Environment")} value={@symptom.environment} />
            <.field
              label={dgettext("dashboard_pulse", "Impact")}
              value={
                @symptom.impact_rate &&
                  "#{format_number(@symptom.impact_rate, fractional_digits: 1)} #{PulseSymptomsLive.impact_unit_label(@symptom.impact_unit)}"
              }
            />
            <.field
              label={dgettext("dashboard_pulse", "Opened")}
              value={timestamp(@symptom.opened_at)}
            />
            <.field
              label={dgettext("dashboard_pulse", "Confidence")}
              value={
                @symptom.p_degraded &&
                  "#{format_number(@symptom.p_degraded * 100, fractional_digits: 0)}%"
              }
            />
            <.field
              label={dgettext("dashboard_pulse", "Last updated")}
              value={timestamp(@symptom.revised_at)}
            />
            <.field
              :if={@symptom.resolved_at}
              label={dgettext("dashboard_pulse", "Resolved")}
              value={timestamp(@symptom.resolved_at)}
            />
            <.field
              :if={outcome(@symptom, @detail.outcome)}
              label={dgettext("dashboard_pulse", "Detection feedback")}
              value={outcome(@symptom, @detail.outcome)}
            />
            <div :if={@source_badges != []}>
              <dt>{dgettext("dashboard_pulse", "Sources")}</dt>
              <dd id="pulse-symptom-sources" data-part="badges">
                <.badge
                  :for={{label, color} <- @source_badges}
                  label={label}
                  color={color}
                  style="light-fill"
                />
              </dd>
            </div>
            <.field
              :for={mute <- @detail.mutes}
              label={PulseSymptomsLive.phenomenon_label(mute.phenomenon)}
              value={
                dgettext("dashboard_pulse", "Muted until %{time}", time: timestamp(mute.expires_at))
              }
            />
          </dl>
        </.card_section>
      </.card>
      <.card
        :if={@measurements}
        id="pulse-symptom-measurements"
        title={dgettext("dashboard_pulse", "Occurrences")}
        icon="chart_arcs"
      >
        <.card_section>
          <div data-part="measurement-plot">
            <%= cond do %>
              <% @measurements.failed -> %>
                <p id="pulse-symptom-measurements-unavailable" data-part="context-text">
                  {dgettext(
                    "dashboard_pulse",
                    "Measurements are unavailable for this window. Missing data is not zero events."
                  )}
                </p>
              <% !@measurements.ok? -> %>
                <.skeleton_chart height="200px" />
              <% true -> %>
                <.chart
                  id="pulse-symptom-occurrences"
                  type="bar"
                  series={[
                    %{
                      name: dgettext("dashboard_pulse", "Events"),
                      data:
                        Enum.map(@measurements.result.occurrence_series, fn [time, count] ->
                          [time * 1000, count]
                        end),
                      barMaxWidth: 32
                    }
                  ]}
                  show_legend={false}
                  extra_options={
                    %{
                      grid: %{left: 16, right: 16, top: 16, bottom: 16, containLabel: true},
                      xAxis: %{type: "time", splitNumber: 4, axisLabel: %{hideOverlap: true}},
                      yAxis: %{min: 0, minInterval: 1, axisLabel: %{formatter: "fn:formatNumber"}},
                      tooltip: %{trigger: "axis", valueFormat: "fn:formatNumber"}
                    }
                  }
                />
            <% end %>
          </div>
        </.card_section>
      </.card>
      <div
        :if={@symptom.suspected_change || !evidence_empty?(@evidence)}
        id="pulse-symptom-technical"
        data-part="evidence-content"
      >
        <.card
          :if={@symptom.suspected_change}
          id="pulse-symptom-change"
          title={dgettext("dashboard_pulse", "Suspected change")}
          icon="git_commit"
        >
          <.card_section>
            <dl data-part="metadata-grid">
              <.field
                label={dgettext("dashboard_pulse", "Kind")}
                value={text(@symptom.suspected_change["kind"])}
              />
              <.field
                label={dgettext("dashboard_pulse", "Reference")}
                value={text(@symptom.suspected_change["ref"])}
              />
              <.field
                label={dgettext("dashboard_pulse", "At")}
                value={change_time(@symptom.suspected_change["at"])}
              />
            </dl>
          </.card_section>
        </.card>
        <.card
          :if={!evidence_empty?(@evidence)}
          id="pulse-symptom-evidence"
          title={dgettext("dashboard_pulse", "Evidence")}
          icon="search"
        >
          <.card_section :if={list(@evidence, "example_ids") != []}>
            <dl data-part="metadata-grid">
              <.field
                label={dgettext("dashboard_pulse", "Example IDs")}
                value={@evidence |> list("example_ids") |> Enum.map_join(", ", &text/1)}
              />
            </dl>
          </.card_section>
          <.card_section :if={list(@evidence, "series_refs") != []}>
            <section data-part="evidence-section">
              <h3 data-part="context-heading">{dgettext("dashboard_pulse", "Series")}</h3>
              <pre :for={series <- list(@evidence, "series_refs")} data-part="code">{text(series["query"])}</pre>
            </section>
          </.card_section>
          <.card_section :if={list(@evidence, "masked_excerpts") != []}>
            <section data-part="evidence-section">
              <h3 data-part="context-heading">{dgettext("dashboard_pulse", "Masked excerpts")}</h3>
              <pre :for={excerpt <- list(@evidence, "masked_excerpts")} data-part="code">{text(excerpt)}</pre>
            </section>
          </.card_section>
        </.card>
      </div>
      <.card
        id="pulse-symptom-revisions"
        title={dgettext("dashboard_pulse", "History")}
        icon="timeline_event"
      >
        <.card_section data-part="symptom-history-section">
          <ol id="pulse-symptom-history" data-part="timeline">
            <li :for={revision <- @detail.revisions} data-part="timeline-item">
              <span
                data-part="timeline-icon"
                data-color={state_icon_color(revision)}
                aria-hidden="true"
              ><.icon name={state_icon(revision.state)} /></span>
              <div data-part="timeline-content">
                <span data-part="timeline-title">{transition_label(revision.transition)}</span>
                <span data-part="timeline-subtitle">{dgettext(
                  "dashboard_pulse",
                  "Severity: %{severity}",
                  severity: PulseSymptomsLive.tier_label(revision.tier)
                )}</span>
              </div>
              <time
                datetime={DateTime.to_iso8601(revision.revised_at)}
                title={timestamp(revision.revised_at)}
                data-part="timeline-time"
              >
                {DateFormatter.from_now(revision.revised_at)}
              </time>
            </li>
          </ol>
        </.card_section>
      </.card>
    </div>
    """
  end

  attr :label, :string, required: true
  attr :value, :string, default: nil

  defp field(assigns) do
    ~H"""
    <div>
      <dt>{@label}</dt>
      <dd>{if @value in [nil, ""], do: dgettext("dashboard_pulse", "Not recorded"), else: @value}</dd>
    </div>
    """
  end

  defp state_icon(:open), do: "alert_triangle"
  defp state_icon(:merged), do: "git_merge"
  defp state_icon(_state), do: "circle_check"

  defp state_icon_color(%{state: :open, tier: :page}), do: "destructive"
  defp state_icon_color(%{state: :open}), do: "warning"
  defp state_icon_color(%{state: :merged}), do: "neutral"
  defp state_icon_color(_symptom), do: "success"

  defp outcome_options,
    do: [
      {"bad", dgettext("dashboard_pulse", "Yes, a real problem")},
      {"fine", dgettext("dashboard_pulse", "No, not a problem")}
    ]

  defp outcome_label(%{outcome: :bad}), do: dgettext("dashboard_pulse", "Real problem")
  defp outcome_label(%{outcome: :fine}), do: dgettext("dashboard_pulse", "Not a problem")
  defp outcome_label(_outcome), do: dgettext("dashboard_pulse", "Was this a real problem?")

  defp transition_label(:opened), do: dgettext("dashboard_pulse", "Opened")
  defp transition_label(:escalated), do: dgettext("dashboard_pulse", "Escalated")
  defp transition_label(:deescalated), do: dgettext("dashboard_pulse", "De-escalated")
  defp transition_label(:merged), do: dgettext("dashboard_pulse", "Merged")
  defp transition_label(:resolved), do: dgettext("dashboard_pulse", "Resolved")
  defp transition_label(:reopened), do: dgettext("dashboard_pulse", "Reopened")
  defp transition_label(:annotated), do: dgettext("dashboard_pulse", "Annotated")

  defp timestamp(%DateTime{} = time), do: Calendar.strftime(time, "%Y-%m-%d %H:%M UTC")

  # The evaluator's ISO 8601 time, in the page's format when it parses.
  defp change_time(value) when is_binary(value) do
    case DateTime.from_iso8601(value) do
      {:ok, time, _offset} -> timestamp(time)
      _ -> value
    end
  end

  defp change_time(value), do: text(value)

  defp outcome(_symptom, %{outcome: :bad}), do: dgettext("dashboard_pulse", "Real problem")
  defp outcome(_symptom, %{outcome: :fine}), do: dgettext("dashboard_pulse", "Not a problem")
  defp outcome(%{outcome: %{} = outcome}, nil), do: outcome |> Map.get("label", outcome["kind"]) |> text()
  defp outcome(_symptom, nil), do: nil

  defp source_badges(phenomena) do
    labels = %{
      "metric" => {dgettext("dashboard_pulse", "Metrics"), "focus"},
      "trace" => {dgettext("dashboard_pulse", "Traces"), "primary"},
      "log" => {dgettext("dashboard_pulse", "Logs"), "information"},
      "error" => {dgettext("dashboard_pulse", "Errors"), "secondary"},
      "probe" => {dgettext("dashboard_pulse", "Probes"), "neutral"},
      "k8s" => {dgettext("dashboard_pulse", "Kubernetes events"), "neutral"},
      "deploy" => {dgettext("dashboard_pulse", "Deployments"), "neutral"},
      "presence" => {dgettext("dashboard_pulse", "Telemetry health"), "neutral"}
    }

    phenomena
    |> Enum.flat_map(&Map.get(&1, "sources", []))
    |> Enum.map(&(&1 |> String.split(".", parts: 2) |> hd()))
    |> Enum.uniq()
    |> Enum.sort()
    |> Enum.map(&Map.get(labels, &1, {&1, "neutral"}))
  end

  defp evidence_empty?(evidence), do: Enum.all?(~w(example_ids series_refs masked_excerpts), &(list(evidence, &1) == []))

  defp list(map, key) do
    case map[key] do
      values when is_list(values) -> values
      _ -> []
    end
  end

  # Values from the evaluator's JSON are shown as text whatever their type.
  defp text(value) when is_binary(value), do: value
  defp text(nil), do: nil
  defp text(value) when is_number(value) or is_boolean(value), do: to_string(value)
  defp text(value), do: JSON.encode!(value)
end
