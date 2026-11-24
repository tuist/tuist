defmodule TuistWeb.SnapshotHistoryLive do
  @moduledoc """
  One snapshot's history in a set (`Tuist.Snapshots.image_history/3`): its
  versions on the default branch, newest first, each against the version
  before it. Each entry opens the snapshot run it came from.
  """
  use TuistWeb, :live_view
  use Noora

  alias Tuist.FeatureFlags
  alias Tuist.Snapshots
  alias Tuist.Utilities.DateFormatter
  alias TuistWeb.Errors.NotFoundError
  alias TuistWeb.SnapshotBuildLive
  alias TuistWeb.SnapshotsLive
  alias TuistWeb.Utilities.SHA

  @modes ~w(side_by_side diff wipe onion)

  def mount(
        %{"set_name" => set_name, "name" => name},
        _session,
        %{assigns: %{selected_project: project, selected_account: account}} = socket
      ) do
    if !FeatureFlags.snapshots_enabled?(account), do: raise(NotFoundError)

    name = name |> List.wrap() |> Enum.join("/")
    %{versions: versions, more?: more?} = Snapshots.image_history(project, set_name, name)
    if versions == [], do: raise(NotFoundError)

    # A snapshot removed from the default branch shows how it last looked.
    latest = Enum.find(versions, hd(versions), & &1.image.content_hash)
    title = latest.image.display_name || name

    {:ok,
     socket
     |> assign(
       :head_title,
       "#{title} · #{dgettext("dashboard_snapshots", "Snapshots")} · #{account.name}/#{project.name} · Tuist"
     )
     |> assign(:set_name, set_name)
     |> assign(:name, name)
     |> assign(:title, title)
     |> assign(:latest, latest.image)
     |> assign(:versions, versions)
     |> assign(:more?, more?)
     |> assign(:modes, %{})}
  end

  # Each changed version picks its own comparison mode, next to its images.
  def handle_event("select_mode", %{"image" => image_id, "mode" => mode}, socket) when mode in @modes do
    {:noreply, update(socket, :modes, &Map.put(&1, image_id, mode))}
  end

  def handle_event("load_more", _params, %{assigns: assigns} = socket) do
    %{versions: older, more?: more?} =
      Snapshots.image_history(assigns.selected_project, assigns.set_name, assigns.name,
        before: List.last(assigns.versions).build
      )

    {:noreply, socket |> assign(:versions, assigns.versions ++ older) |> assign(:more?, more?)}
  end

  def render(assigns) do
    ~H"""
    <div id="snapshot-history">
      <div data-part="action-buttons">
        <.button
          variant="secondary"
          size="medium"
          label={dgettext("dashboard_snapshots", "Snapshots")}
          navigate={~p"/#{@selected_account.name}/#{@selected_project.name}/snapshots"}
        >
          <:icon_left><.icon name="arrow_left" /></:icon_left>
        </.button>
      </div>

      <.card icon="photo" title={@title} data-part="details">
        <.card_section data-part="details-section">
          <div :if={@latest.content_hash} data-part="stage">
            <img
              src={SnapshotBuildLive.image_src(@selected_account, @selected_project, @latest, :head)}
              alt={@title}
            />
          </div>
          <div data-part="metadata-grid">
            <div data-part="metadata">
              <span data-part="title">{dgettext("dashboard_snapshots", "Set")}</span>
              <span data-part="label">{@set_name}</span>
            </div>
            <div data-part="metadata">
              <span data-part="title">{dgettext("dashboard_snapshots", "File")}</span>
              <span data-part="label">{@name}</span>
            </div>
            <div :if={@latest.group} data-part="metadata">
              <span data-part="title">{dgettext("dashboard_snapshots", "Group")}</span>
              <.link
                navigate={
                  ~p"/#{@selected_account.name}/#{@selected_project.name}/snapshots?group=#{@latest.group}"
                }
                data-part="label"
              >
                {@latest.group}
              </.link>
            </div>
            <div :if={map_size(@latest.tags || %{}) > 0} data-part="metadata">
              <span data-part="title">{dgettext("dashboard_snapshots", "Tags")}</span>
              <span data-part="tags">
                <.badge
                  :for={{key, value} <- Enum.sort(@latest.tags)}
                  label={"#{key}: #{value}"}
                  color="neutral"
                  style="light-fill"
                  size="small"
                />
              </span>
            </div>
          </div>
        </.card_section>
      </.card>

      <.card
        icon="history"
        title={dgettext("dashboard_snapshots", "Timeline")}
        data-part="history"
      >
        <.card_section data-part="history-section">
          <ol data-part="timeline">
            <li
              :for={{entry, index} <- Enum.with_index(@versions)}
              id={"snapshot-history-#{entry.image.id}"}
              data-part="entry"
            >
              <span
                data-part="marker"
                data-status={entry.image.status}
                title={SnapshotBuildLive.status_label(entry.image.status)}
                aria-label={SnapshotBuildLive.status_label(entry.image.status)}
              >
                <.icon name={SnapshotsLive.change_icon(entry.image.status)} />
              </span>
              <div data-part="entry-header">
                <div data-part="entry-title">
                  <.link navigate={
                    ~p"/#{@selected_account.name}/#{@selected_project.name}/snapshots/#{entry.build.id}?status=#{entry.image.status}&q=#{@name}"
                  }>
                    {SnapshotBuildLive.status_label(entry.image.status)}
                  </.link>
                  <span data-part="entry-meta">{entry_description(entry)}</span>
                </div>
                <div data-part="entry-badges">
                  <.badge
                    :if={index == 0 and entry.image.status != "removed"}
                    label={dgettext("dashboard_snapshots", "Current")}
                    color="success"
                    style="light-fill"
                    size="small"
                  />
                </div>
              </div>
              <.button_group
                :if={entry.image.status == "changed"}
                size="small"
                data-part="modes"
              >
                <.button_group_item
                  :for={mode <- ~w(side_by_side diff wipe onion)}
                  label={mode_label(mode)}
                  phx-click="select_mode"
                  phx-value-image={entry.image.id}
                  phx-value-mode={mode}
                  data-selected={Map.get(@modes, entry.image.id, "side_by_side") == mode}
                />
              </.button_group>
              <SnapshotBuildLive.image_viewer
                image={entry.image}
                mode={Map.get(@modes, entry.image.id, "side_by_side")}
                src={
                  &SnapshotBuildLive.image_src(@selected_account, @selected_project, entry.image, &1)
                }
              />
            </li>
          </ol>
          <div :if={@more?} data-part="load-more">
            <.button
              variant="secondary"
              size="medium"
              label={dgettext("dashboard_snapshots", "Show older versions")}
              phx-click="load_more"
            />
          </div>
        </.card_section>
      </.card>
    </div>
    """
  end

  defp entry_description(entry) do
    [
      SHA.format_commit_sha(entry.build.git_commit_sha),
      entry.build.pull_request_number && "##{entry.build.pull_request_number}",
      DateFormatter.from_now(entry.build.inserted_at),
      entry.image.status == "changed" && entry.image.diff_ratio &&
        dgettext("dashboard_snapshots", "%{percentage}% of pixels changed",
          percentage: format_ratio(entry.image.diff_ratio)
        )
    ]
    |> Enum.reject(&(&1 in [nil, false]))
    |> Enum.join(" · ")
  end

  defp mode_label("side_by_side"), do: dgettext("dashboard_snapshots", "Side by side")
  defp mode_label("diff"), do: dgettext("dashboard_snapshots", "Diff")
  defp mode_label("wipe"), do: dgettext("dashboard_snapshots", "Wipe")
  defp mode_label("onion"), do: dgettext("dashboard_snapshots", "Onion")

  defp format_ratio(ratio) do
    percentage = ratio * 100
    if percentage < 0.01, do: "<0.01", else: :erlang.float_to_binary(percentage, decimals: 2)
  end
end
