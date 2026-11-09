defmodule TuistWeb.Docs.ReleaseStatus do
  @moduledoc false
  use Phoenix.Component
  use Gettext, backend: TuistWeb.Gettext

  import Noora.Alert, only: [alert: 1]
  import Noora.Badge, only: [badge: 1]
  import Noora.Button, only: [link_button: 1]
  import Noora.Card, only: [card: 1, card_section: 1]
  import Noora.LineDivider, only: [line_divider: 1]
  import Noora.Table, only: [table: 1, text_cell: 1]

  attr :status, :any, required: true
  attr :components, :list, required: true
  attr :calendar_url, :string, default: nil

  def panel(assigns) do
    ~H"""
    <div id="docs-release-status" phx-hook="DocsReleaseStatus" aria-live="polite">
      <p data-part="release-note">
        {if @calendar_url,
          do: dgettext("docs", "Published versions come from GitHub."),
          else:
            dgettext(
              "docs",
              "Published versions come from GitHub. Future windows are scheduled, not guaranteed."
            )}
        {dgettext("docs", "Times shown in")} <span data-timezone>UTC</span>.
      </p>
      <.alert
        :if={!@status.ok? && !@status.failed}
        status="information"
        type="secondary"
        title={dgettext("docs", "Loading release status…")}
        role="status"
      />
      <.alert
        :if={@status.failed}
        status="warning"
        type="secondary"
        title={
          dgettext("docs", "Release status is unavailable. Check GitHub for the latest releases.")
        }
        role="status"
      />
      <noscript>
        <p>{dgettext("docs", "Enable JavaScript to load live release status and the calendar.")}</p>
      </noscript>
      <.link_button
        :if={!@status.ok? || @status.failed}
        href="https://github.com/tuist/tuist/releases"
        label={dgettext("docs", "View releases on GitHub")}
      />
      <section
        :for={component <- @components}
        :if={@status.ok? && !@status.failed}
        data-part="release-component"
        data-component={component}
        data-state={@status.result[component].state}
      >
        <% data = @status.result[component] %>
        <.card title={component_name(component)} icon="calendar_week">
          <:actions>
            <.badge label={state_label(data.state)} color={state_color(data.state)} dot />
          </:actions>
          <.card_section>
            <.alert
              :if={data.state == :stale}
              status="warning"
              type="secondary"
              size="large"
              title={state_label(data.state)}
              description={
                dgettext(
                  "docs",
                  "GitHub could not be refreshed. These are the last successfully checked versions; the calendar may be outdated."
                )
              }
              role="status"
            />
            <.alert
              :if={data.state == :unavailable}
              status="warning"
              type="secondary"
              size="large"
              title={state_label(data.state)}
              description={
                dgettext(
                  "docs",
                  "Release data is unavailable. No release dates or versions have been inferred."
                )
              }
              role="status"
            />
            <dl :if={data.state != :unavailable} data-part="release-channels">
              <div :for={channel <- [:stable, :rc, :canary]} data-channel={channel}>
                <dt>{channel_label(channel)}</dt>
                <dd :if={data[channel]}>
                  <.link_button href={data[channel].url} label={data[channel].version} dir="ltr" />
                  <span :if={!@calendar_url} data-part="release-published">
                    {dgettext("docs", "Published")}
                    <.timestamp value={data[channel].published_at} />
                  </span>
                </dd>
                <dd :if={!data[channel]} data-part="release-empty">
                  {if channel == :rc,
                    do: dgettext("docs", "No pending candidate"),
                    else: dgettext("docs", "Not available")}
                </dd>
              </div>
            </dl>
            <p :if={@calendar_url && data.checked_at} data-part="release-note">
              {dgettext("docs", "Last checked")} <.timestamp value={data.checked_at} />
            </p>
          </.card_section>
          <.card_section :if={!@calendar_url && data.state != :unavailable}>
            <% history = Map.get(data, :history) %>
            <div data-part="release-calendar-header">
              <h4>{dgettext("docs", "Past releases")}</h4>
              <span data-part="release-note">{dgettext("docs", "Last two weeks")}</span>
            </div>
            <p :if={!history} data-part="release-note">
              {dgettext("docs", "Release history could not be loaded. View past releases on GitHub.")}
            </p>
            <div :if={history} data-part="release-history">
              <details :if={history.earlier != []} id={"docs-earlier-releases-#{component}"}>
                <summary>{dgettext("docs", "Show earlier releases")}</summary>
                <.history_table
                  id={"docs-earlier-history-#{component}"}
                  releases={history.earlier}
                />
              </details>
              <.history_table
                :if={history.recent != []}
                id={"docs-recent-history-#{component}"}
                releases={history.recent}
              />
              <p :if={history.recent == []} data-part="release-note">
                {dgettext("docs", "No releases found in this snapshot for the last two weeks.")}
              </p>
            </div>
            <footer data-part="release-history-footer">
              <p :if={history && history.limited?} data-part="release-note">
                {dgettext("docs", "Showing a recent snapshot, not the full release history.")}
              </p>
              <p data-part="release-note">
                {dgettext(
                  "docs",
                  "Patch releases include on-demand fixes and backports; they do not have a weekly schedule. Canary updates are shown above, not in the calendar."
                )}
              </p>
              <.link_button
                href={releases_url(component)}
                label={dgettext("docs", "Full release history on GitHub")}
              />
            </footer>
          </.card_section>
          <.card_section :if={!@calendar_url && data.state != :unavailable}>
            <.line_divider text={dgettext("docs", "Today")} />
            <div data-part="release-calendar-header">
              <h4>{dgettext("docs", "Upcoming release windows")}</h4>
              <p :if={data.promotion} data-part="release-note">
                {dgettext("docs", "Latest promotion:")}
                <.link_button href={data.promotion.url} label={promotion_label(data.promotion)} />
              </p>
            </div>
            <div :if={data.schedule != []} data-part="release-calendar">
              <.table
                id={"docs-release-calendar-#{component}"}
                rows={Enum.with_index(Enum.take(data.schedule, 3))}
                row_key={fn {window, _index} -> "#{component}-#{DateTime.to_unix(window)}" end}
              >
                <:col :let={{window, _index}} label={dgettext("docs", "Scheduled")}>
                  <span data-part="release-date"><.timestamp value={window} /></span>
                </:col>
                <:col :let={{_window, index}} label={dgettext("docs", "Release")}>
                  <.text_cell label={
                    if index == 0 && data.rc && data.state == :fresh,
                      do:
                        dgettext("docs", "Target: %{version} stable",
                          version: stable_version(data.rc.version)
                        ),
                      else: dgettext("docs", "Version to be confirmed")
                  } />
                </:col>
              </.table>
            </div>
            <p :if={data.schedule != []} data-part="release-note">
              {dgettext(
                "docs",
                "Stable releases require a ready candidate. A successful release creates the next candidate."
              )}
            </p>
            <p :if={data.schedule == []} data-part="release-note">
              {dgettext(
                "docs",
                "The release schedule could not be verified. Check the workflow for upcoming releases."
              )}
            </p>
          </.card_section>
          <.card_section :if={!@calendar_url}>
            <footer data-part="release-footer">
              <span :if={data.checked_at}>
                {dgettext("docs", "Last checked")} <.timestamp value={data.checked_at} />
              </span>
              <.link_button
                href={data.workflow_url}
                label={dgettext("docs", "View release workflow")}
              />
            </footer>
          </.card_section>
        </.card>
      </section>
      <.link_button
        :if={@calendar_url}
        href={@calendar_url}
        label={dgettext("docs", "View release calendar")}
      />
    </div>
    """
  end

  attr :id, :string, required: true
  attr :releases, :list, required: true

  defp history_table(assigns) do
    ~H"""
    <.table id={@id} rows={@releases} row_key={& &1.version}>
      <:col :let={release} label={dgettext("docs", "Published")}>
        <span data-part="release-date"><.timestamp value={release.published_at} /></span>
      </:col>
      <:col :let={release} label={dgettext("docs", "Release")}>
        <div data-part="release-history-version">
          <.badge label={history_label(release.kind)} color={history_color(release.kind)} />
          <.link_button href={release.url} label={release.version} dir="ltr" />
        </div>
      </:col>
    </.table>
    """
  end

  attr :value, :any, required: true

  defp timestamp(assigns) do
    ~H"""
    <time datetime={DateTime.to_iso8601(@value)} data-release-time>
      {Calendar.strftime(@value, "%b %-d, %Y, %H:%M UTC")}
    </time>
    """
  end

  defp component_name(:cli), do: dgettext("docs", "Tuist CLI")
  defp component_name(:server), do: dgettext("docs", "Tuist Server")
  defp component_name(:kura), do: "Kura"

  defp channel_label(:stable), do: dgettext("docs", "Stable · recommended")
  defp channel_label(:rc), do: dgettext("docs", "Release candidate")
  defp channel_label(:canary), do: dgettext("docs", "Canary")

  defp history_label(:stable), do: dgettext("docs", "Stable")
  defp history_label(:rc), do: dgettext("docs", "Release candidate")
  defp history_label(:patch), do: dgettext("docs", "Patch")

  defp history_color(:stable), do: "success"
  defp history_color(:rc), do: "information"
  defp history_color(:patch), do: "neutral"

  defp releases_url(:cli), do: "https://github.com/tuist/tuist/releases"
  defp releases_url(component), do: "https://github.com/tuist/tuist/releases?q=tag%3A#{component}%40"

  defp state_label(:fresh), do: dgettext("docs", "Up to date")
  defp state_label(:stale), do: dgettext("docs", "Outdated data")
  defp state_label(:unavailable), do: dgettext("docs", "Unavailable")

  defp state_color(:fresh), do: "success"
  defp state_color(:stale), do: "warning"
  defp state_color(:unavailable), do: "neutral"

  defp promotion_label(%{status: status}) when status != "completed", do: dgettext("docs", "In progress")
  defp promotion_label(%{conclusion: "success"}), do: dgettext("docs", "Succeeded")
  defp promotion_label(%{conclusion: "failure"}), do: dgettext("docs", "Failed")
  defp promotion_label(%{conclusion: "cancelled"}), do: dgettext("docs", "Cancelled")
  defp promotion_label(_run), do: dgettext("docs", "Not completed successfully")

  defp stable_version(version), do: version |> Version.parse!() |> Map.put(:pre, []) |> to_string()
end
