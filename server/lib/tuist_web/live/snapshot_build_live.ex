defmodule TuistWeb.SnapshotBuildLive do
  @moduledoc """
  Review page of a snapshot build: what changed against its baseline, each
  change side by side, as a diff, with a wipe or an onion skin, grouped and
  tagged as the images' metadata says, and the review that approves or
  rejects the changes.
  """
  use TuistWeb, :live_view
  use Noora

  alias Tuist.Accounts
  alias Tuist.Accounts.Account
  alias Tuist.Accounts.User
  alias Tuist.Authorization
  alias Tuist.FeatureFlags
  alias Tuist.Snapshots
  alias Tuist.Utilities.DateFormatter
  alias TuistWeb.Authentication
  alias TuistWeb.Errors.NotFoundError
  alias TuistWeb.Helpers.VCSLinks
  alias TuistWeb.SnapshotsLive
  alias TuistWeb.Utilities.SHA

  @statuses ~w(changed added removed renamed skipped unchanged)
  @modes ~w(side_by_side diff wipe onion)

  def mount(
        %{"build_id" => build_id},
        _session,
        %{assigns: %{selected_project: project, selected_account: account}} = socket
      ) do
    if !FeatureFlags.snapshots_enabled?(account), do: raise(NotFoundError)

    build =
      case Snapshots.get_build(project, build_id) do
        {:ok, build} -> build
        {:error, :not_found} -> raise NotFoundError
      end

    images = Snapshots.list_images(build)
    user = Authentication.current_user(socket)
    project = Tuist.Repo.preload(project, vcs_connection: :github_app_installation)

    {:ok,
     socket
     |> assign(
       :head_title,
       "#{build.set_name} · #{dgettext("dashboard_snapshots", "Snapshots")} · #{account.name}/#{project.name} · Tuist"
     )
     |> assign(:build, build)
     |> assign(:pull_request_url, pull_request_url(project, build.pull_request_number))
     |> assign(:images, images)
     |> assign(:can_review, Authorization.authorize(:test_update, user, project) == :ok)}
  end

  def handle_params(params, _uri, socket) do
    {:noreply, assign(socket, :review, review_state(params, socket.assigns.images))}
  end

  @doc """
  What the images card shows for the page's query parameters: the selected
  status (the first one with images by default) and, optionally, one of its
  groups, the comparison mode, the search, the sidebar's statuses with the
  groups that match the search, and the selection's images, grouped.
  `show_set: true` groups by set first, for a commit's images pooled over its
  sets.
  """
  def review_state(params, images, opts \\ []) do
    show_set = Keyword.get(opts, :show_set, false)
    counts = Enum.frequencies_by(images, & &1.status)
    default_status = Enum.find(@statuses, "unchanged", &(Map.get(counts, &1, 0) > 0))
    status = if params["status"] in @statuses, do: params["status"], else: default_status

    mode = review_mode(params["mode"])
    search = String.trim(params["q"] || "")
    matching = Enum.filter(images, &matches_search?(&1, String.downcase(search)))
    sidebar = sidebar(matching, counts, show_set)

    status_groups = Enum.find(sidebar, %{groups: []}, &(&1.status == status)).groups
    group = Enum.find_value(status_groups, fn {param, _group, _count} -> if param == params["group"], do: param end)

    grouped_images =
      matching
      |> Enum.filter(&(&1.status == status))
      |> group_images(show_set)
      |> Enum.filter(fn {image_group, _images} -> is_nil(group) or group_param(image_group) == group end)

    visible = Enum.flat_map(grouped_images, fn {_group, group_images} -> group_images end)
    focused_index = Enum.find_index(visible, &(to_string(&1.id) == params["image"]))

    %{
      counts: counts,
      status: status,
      group: group,
      mode: mode,
      search: search,
      sidebar: sidebar,
      grouped_images: grouped_images,
      # Every group gets its own framed block with a header, ungrouped images
      # included, unless the sidebar picked one group or there are none.
      framed_groups: is_nil(group) and Enum.any?(grouped_images, fn {image_group, _} -> image_group end),
      visible_count: length(visible),
      image: focused_index && to_string(Enum.at(visible, focused_index).id),
      focused: focused_index && focused(visible, focused_index)
    }
  end

  defp review_mode(mode) when mode in @modes, do: mode
  # Links from before the wipe mode was named like Sentry's.
  defp review_mode("swipe"), do: "wipe"
  defp review_mode(_mode), do: "side_by_side"

  # Each status with images, with the groups of its images that match the search.
  defp sidebar(matching, counts, show_set) do
    for sidebar_status <- visible_statuses(counts) do
      groups = matching |> Enum.filter(&(&1.status == sidebar_status)) |> group_images(show_set)

      %{
        status: sidebar_status,
        count: groups |> Enum.map(fn {_group, group_images} -> length(group_images) end) |> Enum.sum(),
        groups: Enum.map(groups, fn {group, group_images} -> {group_param(group), group, length(group_images)} end)
      }
    end
  end

  # The image the full-screen viewer shows, where it sits among the
  # selection's images, and its neighbours, which the viewer steps to.
  defp focused(visible, index) do
    %{
      image: Enum.at(visible, index),
      position: index + 1,
      total: length(visible),
      previous: if(index > 0, do: to_string(Enum.at(visible, index - 1).id)),
      next: with(%{id: id} <- Enum.at(visible, index + 1), do: to_string(id))
    }
  end

  # How the `group` query parameter names a group; ungrouped images have a name of their own.
  defp group_param(nil), do: "-"
  defp group_param(group), do: group

  def handle_event("search", %{"q" => search}, socket) do
    {:noreply, push_patch(socket, to: review_query(socket.assigns.review, q: search), replace: true)}
  end

  def handle_event(event, _params, %{assigns: %{selected_project: project, build: build}} = socket)
      when event in ["approve", "reject"] do
    user = Authentication.current_user(socket)

    if Authorization.authorize(:test_update, user, project) == :ok do
      {:ok, _} =
        if event == "approve",
          do: Snapshots.approve_build(build, user.account),
          else: Snapshots.reject_build(build, user.account)

      {:ok, build} = Snapshots.get_build(project, build.id)
      {:noreply, assign(socket, :build, build)}
    else
      {:noreply, socket}
    end
  end

  defp matches_search?(_image, ""), do: true

  defp matches_search?(image, search) do
    [image.name, image.display_name, image.group | Enum.flat_map(image.tags || %{}, fn {k, v} -> [k, v, "#{k}=#{v}"] end)]
    |> Enum.reject(&is_nil/1)
    |> Enum.any?(&String.contains?(String.downcase(&1), search))
  end

  # Images keep their order (by status, then name) within a group; groups are
  # ordered by name, with ungrouped images last.
  # The file name only adds information when it is more than the display name plus its extension.
  defp distinct_file_name?(%{display_name: nil}), do: false
  defp distinct_file_name?(image), do: Path.rootname(image.name) != image.display_name

  defp group_images(images, show_set) do
    images
    |> Enum.group_by(fn image ->
      if show_set, do: Enum.join(Enum.reject([image.set_name, image.group], &is_nil/1), " · "), else: image.group
    end)
    |> Enum.sort_by(fn {group, _} -> {is_nil(group), group} end)
  end

  defp review_query(review, overrides) do
    query =
      [status: review.status, group: review.group, mode: review.mode, q: review.search, image: review.image]
      |> Keyword.merge(overrides)
      |> Enum.reject(fn {_key, value} -> value in [nil, ""] end)

    "?" <> URI.encode_query(query)
  end

  def render(assigns) do
    ~H"""
    <div id="snapshot-build">
      <div data-part="action-buttons">
        <.button
          variant="secondary"
          size="medium"
          label={dgettext("dashboard_snapshots", "Snapshots")}
          navigate={~p"/#{@selected_account.name}/#{@selected_project.name}/snapshots"}
        >
          <:icon_left><.icon name="arrow_left" /></:icon_left>
        </.button>
        <div
          :if={@can_review and Snapshots.reviewable?(@build, @selected_project)}
          data-part="review-buttons"
        >
          <.button
            :if={Snapshots.status(@build, @selected_project) != "approved"}
            id="approve-snapshot-build"
            label={dgettext("dashboard_snapshots", "Approve changes")}
            size="medium"
            phx-click="approve"
          >
            <:icon_left><.icon name="check" /></:icon_left>
          </.button>
          <.button
            :if={Snapshots.status(@build, @selected_project) != "rejected"}
            id="reject-snapshot-build"
            label={dgettext("dashboard_snapshots", "Reject changes")}
            variant="destructive"
            size="medium"
            phx-click="reject"
          >
            <:icon_left><.icon name="close" /></:icon_left>
          </.button>
        </div>
      </div>

      <.card icon="photo" title={@build.set_name} data-part="details">
        <.card_section data-part="details-section">
          <div data-part="metadata-grid">
            <div data-part="metadata">
              <span data-part="title">{dgettext("dashboard_snapshots", "Status")}</span>
              <.verdict_badge status={Snapshots.status(@build, @selected_project)} />
            </div>
            <div data-part="metadata">
              <span data-part="title">{dgettext("dashboard_snapshots", "Branch")}</span>
              <span data-part="label">{@build.git_branch || dgettext("dashboard_snapshots", "None")}</span>
            </div>
            <div data-part="metadata">
              <span data-part="title">{dgettext("dashboard_snapshots", "Commit SHA")}</span>
              <span data-part="label">{SHA.format_commit_sha(@build.git_commit_sha)}</span>
            </div>
            <.pull_request_metadata label={pull_request_label(@build)} url={@pull_request_url} />
            <div data-part="metadata">
              <span data-part="title">{dgettext("dashboard_snapshots", "Baseline")}</span>
              <%= if @build.baseline_build do %>
                <.link_button
                  navigate={
                    ~p"/#{@selected_account.name}/#{@selected_project.name}/snapshots/#{@build.baseline_build.id}"
                  }
                  label={
                    "#{@build.baseline_build.git_branch || "?"} · #{SHA.format_commit_sha(@build.baseline_build.git_commit_sha)}"
                  }
                  variant="secondary"
                  size="medium"
                  underline
                />
              <% else %>
                <span data-part="label">{dgettext(
                  "dashboard_snapshots",
                  "None, first build of the set"
                )}</span>
              <% end %>
            </div>
            <.review_metadata id="snapshot-build-reviewer" reviewer={reviewer(@build)}>
              <.link_button
                :if={@build.approved_from_build}
                navigate={
                  ~p"/#{@selected_account.name}/#{@selected_project.name}/snapshots/#{@build.approved_from_build.id}"
                }
                label={
                  dgettext("dashboard_snapshots", "Same changes as %{commit}",
                    commit: SHA.format_commit_sha(@build.approved_from_build.git_commit_sha)
                  )
                }
                variant="secondary"
                size="small"
                underline
              />
            </.review_metadata>
            <div data-part="metadata">
              <span data-part="title">{dgettext("dashboard_snapshots", "Uploaded")}</span>
              <span data-part="label">{DateFormatter.from_now(@build.inserted_at)}</span>
            </div>
            <div data-part="metadata">
              <span data-part="title">{dgettext("dashboard_snapshots", "Snapshots")}</span>
              <span data-part="label">{length(@images)}</span>
            </div>
          </div>
        </.card_section>
      </.card>

      <.images_card
        review={@review}
        processing={@build.state in ["uploading", "processing"]}
        query={&review_query(@review, &1)}
        src={&image_src(@selected_account, @selected_project, &1, &2)}
      />
    </div>
    """
  end

  attr :review, :map, required: true, doc: "From `review_state/3`."
  attr :processing, :boolean, default: false
  attr :query, :any, required: true, doc: "Builds the patch for the given review overrides."
  attr :src, :any, required: true, doc: "An image's URL for a variant: `:head`, `:baseline` or `:diff`."
  slot :filters

  @doc """
  The review of the build and commit pages, laid out like Sentry's: a
  collapsible sidebar beside the images card with the search, the filters and
  each status with the groups in it, and the selected status's or group's
  images in the card, with the comparison modes. Collapsing it is client-side
  and survives the page's patches, so the images can take the page's width.
  """
  def images_card(assigns) do
    ~H"""
    <div
      id="snapshot-review"
      data-part="review"
      data-sidebar={if @processing, do: "none", else: "open"}
    >
      <aside
        :if={not @processing}
        id="snapshot-review-sidebar"
        data-part="sidebar"
        aria-label={dgettext("dashboard_snapshots", "Image statuses")}
      >
        <.form for={%{}} phx-change="search" phx-debounce="200" data-part="search">
          <.text_input
            type="search"
            id="search-snapshot-images"
            name="q"
            value={@review.search}
            placeholder={dgettext("dashboard_snapshots", "Search snapshots...")}
            show_suffix={false}
          />
        </.form>
        {render_slot(@filters)}
        <nav data-part="statuses">
          <div :for={entry <- @review.sidebar} data-part="status-section">
            <.link
              patch={@query.(status: entry.status, group: nil, image: nil)}
              data-part="item"
              data-status={entry.status}
              aria-current={(@review.status == entry.status and is_nil(@review.group)) && "true"}
            >
              <.tab_menu_vertical
                label={status_label(entry.status)}
                data-selected={@review.status == entry.status and is_nil(@review.group)}
              >
                <:icon_left><.icon name={SnapshotsLive.change_icon(entry.status)} /></:icon_left>
                <:icon_right><span data-part="count">{entry.count}</span></:icon_right>
              </.tab_menu_vertical>
            </.link>
            <div
              :if={entry.groups != [{"-", nil, entry.count}] and entry.groups != []}
              data-part="groups"
            >
              <.link
                :for={{param, group, count} <- entry.groups}
                patch={@query.(status: entry.status, group: param, image: nil)}
                data-part="item"
                aria-current={(@review.status == entry.status and @review.group == param) && "true"}
              >
                <.tab_menu_vertical
                  label={group || dgettext("dashboard_snapshots", "Ungrouped")}
                  data-selected={@review.status == entry.status and @review.group == param}
                  title={group || dgettext("dashboard_snapshots", "Ungrouped")}
                >
                  <:icon_right><span data-part="count">{count}</span></:icon_right>
                </.tab_menu_vertical>
              </.link>
            </div>
          </div>
        </nav>
      </aside>
      <.card
        icon={if @processing, do: "layout_grid", else: SnapshotsLive.change_icon(@review.status)}
        title={
          if @processing,
            do: dgettext("dashboard_snapshots", "Images"),
            else: selection_title(@review)
        }
        data-part="images"
        data-status={not @processing && @review.status}
      >
        <:actions :if={not @processing and @review.status == "changed"}>
          <.button_group size="medium" data-part="modes">
            <.button_group_item
              :for={mode <- ~w(side_by_side diff wipe onion)}
              label={mode_label(mode)}
              patch={@query.(mode: mode)}
              data-selected={@review.mode == mode}
            />
          </.button_group>
        </:actions>
        <.card_section data-part="images-section">
          <p :if={@processing} data-part="notice">
            {dgettext("dashboard_snapshots", "Still being compared with the baseline.")}
          </p>
          <div :if={not @processing} data-part="main">
            <p :if={@review.visible_count == 0} data-part="notice">
              {if @review.search == "",
                do: dgettext("dashboard_snapshots", "No images in this category."),
                else: dgettext("dashboard_snapshots", "No images in this category match the search.")}
            </p>
            <section
              :for={{group, images} <- @review.grouped_images}
              data-part="group"
              data-framed={@review.framed_groups}
            >
              <header :if={@review.framed_groups} data-part="group-header">
                <.icon name="folder" />
                <span data-part="group-title">
                  {group || dgettext("dashboard_snapshots", "Ungrouped")}
                </span>
                <span data-part="group-count">{length(images)}</span>
              </header>
              <div
                :for={image <- images}
                id={"snapshot-image-#{image.id}"}
                data-part="image"
                data-status={image.status}
              >
                <div data-part="image-header">
                  <span data-part="image-name">{image.display_name || image.name}</span>
                  <.ghost_button
                    variant="secondary"
                    patch={@query.(image: to_string(image.id))}
                    size="small"
                    data-part="expand"
                    aria-label={
                      dgettext("dashboard_snapshots", "Open %{name} full screen",
                        name: image.display_name || image.name
                      )
                    }
                    title={dgettext("dashboard_snapshots", "Open full screen")}
                  >
                    <.maximize />
                  </.ghost_button>
                  <span :if={image.diff_ratio && image.status == "changed"} data-part="image-ratio">
                    {dgettext("dashboard_snapshots", "%{percentage}% of pixels changed",
                      percentage: format_ratio(image.diff_ratio)
                    )}
                  </span>
                  <span :if={image.diff_ratio && image.status == "unchanged"} data-part="image-ratio">
                    {dgettext(
                      "dashboard_snapshots",
                      "%{percentage}% of pixels differ, within the %{threshold}% threshold",
                      percentage: format_ratio(image.diff_ratio),
                      threshold: format_ratio(image.diff_threshold || 0.0)
                    )}
                  </span>
                  <span :if={image.status == "renamed"} data-part="image-ratio">
                    {dgettext("dashboard_snapshots", "Renamed from %{name}", name: image.renamed_from)}
                  </span>
                  <span :if={image.status == "skipped"} data-part="image-ratio">
                    {dgettext(
                      "dashboard_snapshots",
                      "Not rendered in this run; carried over from the baseline"
                    )}
                  </span>
                  <span :if={dimensions_changed?(image)} data-part="image-ratio">
                    {"#{image.baseline_width}×#{image.baseline_height} → #{image.width}×#{image.height}"}
                  </span>
                </div>
                <div
                  :if={distinct_file_name?(image) || map_size(image.tags || %{}) > 0}
                  data-part="image-meta"
                >
                  <span :if={distinct_file_name?(image)} data-part="image-file">{image.name}</span>
                  <.badge
                    :for={{key, value} <- Enum.sort(image.tags || %{})}
                    label={"#{key}: #{value}"}
                    color="neutral"
                    style="light-fill"
                    size="small"
                  />
                </div>
                <.image_viewer image={image} mode={@review.mode} src={&@src.(image, &1)} />
              </div>
            </section>
          </div>
        </.card_section>
      </.card>
      <.fullscreen_viewer :if={@review.focused} review={@review} query={@query} src={@src} />
    </div>
    """
  end

  attr :review, :map, required: true
  attr :query, :any, required: true
  attr :src, :any, required: true

  # One image of the selection over the whole window, as Sentry's expand
  # opens one: its comparison as large as the window allows, the comparison
  # modes, and the previous and next images of the selection, also on the
  # arrow keys. Escape or the close button returns to the list.
  defp fullscreen_viewer(assigns) do
    assigns = assign(assigns, :focused, assigns.review.focused)

    ~H"""
    <div
      id="snapshot-fullscreen"
      data-part="fullscreen"
      phx-hook="SnapshotFullscreen"
      role="dialog"
      aria-modal="true"
      aria-label={@focused.image.display_name || @focused.image.name}
      tabindex="-1"
    >
      <div data-part="fullscreen-header">
        <div data-part="fullscreen-title">
          <span data-part="selection-status" data-status={@focused.image.status}>
            <.icon name={SnapshotsLive.change_icon(@focused.image.status)} />
            {status_label(@focused.image.status)}
          </span>
          <span data-part="image-name">{@focused.image.display_name || @focused.image.name}</span>
          <span
            :if={@focused.image.diff_ratio && @focused.image.status == "changed"}
            data-part="image-ratio"
          >
            {dgettext("dashboard_snapshots", "%{percentage}% of pixels changed",
              percentage: format_ratio(@focused.image.diff_ratio)
            )}
          </span>
        </div>
        <.button_group :if={@focused.image.status == "changed"} size="medium" data-part="modes">
          <.button_group_item
            :for={mode <- ~w(side_by_side diff wipe onion)}
            label={mode_label(mode)}
            patch={@query.(mode: mode)}
            data-selected={@review.mode == mode}
          />
        </.button_group>
        <div data-part="fullscreen-nav">
          <span data-part="position">{"#{@focused.position} / #{@focused.total}"}</span>
          <.ghost_button
            variant="secondary"
            data-part="previous"
            size="medium"
            patch={@focused.previous && @query.(image: @focused.previous)}
            disabled={is_nil(@focused.previous)}
            aria-label={dgettext("dashboard_snapshots", "Previous image")}
            title={dgettext("dashboard_snapshots", "Previous image")}
          >
            <.chevron_left />
          </.ghost_button>
          <.ghost_button
            variant="secondary"
            data-part="next"
            size="medium"
            patch={@focused.next && @query.(image: @focused.next)}
            disabled={is_nil(@focused.next)}
            aria-label={dgettext("dashboard_snapshots", "Next image")}
            title={dgettext("dashboard_snapshots", "Next image")}
          >
            <.chevron_right />
          </.ghost_button>
          <.ghost_button
            variant="secondary"
            data-part="close"
            size="medium"
            patch={@query.(image: nil)}
            aria-label={dgettext("dashboard_snapshots", "Close full screen")}
            title={dgettext("dashboard_snapshots", "Close full screen")}
          >
            <.close />
          </.ghost_button>
        </div>
      </div>
      <div data-part="fullscreen-body">
        <.image_viewer image={@focused.image} mode={@review.mode} src={&@src.(@focused.image, &1)} />
      </div>
    </div>
    """
  end

  # The card's title names what the sidebar selected: a status, and the group
  # within it when one is picked.
  defp selection_title(%{group: nil} = review), do: status_label(review.status)

  defp selection_title(%{group: "-"} = review),
    do: "#{status_label(review.status)} / #{dgettext("dashboard_snapshots", "Ungrouped")}"

  defp selection_title(review), do: "#{status_label(review.status)} / #{review.group}"

  attr :image, :map, required: true
  attr :mode, :string, required: true
  attr :src, :any, required: true

  @doc """
  An image as its status shows it: a changed one against its baseline in
  `mode`, where side by side shows the two images and diff their difference.
  """
  # Wipe and onion overlay the new image on the baseline, like Sentry's
  # modes: the SnapshotCompare hook moves one position (dragged on the image
  # or on the slider) that wipe uses as the boundary and onion as the new
  # image's opacity.
  def image_viewer(%{image: %{status: "changed"}, mode: mode} = assigns) when mode in ["wipe", "onion"] do
    ~H"""
    <div
      id={"compare-#{@image.id}"}
      phx-hook="SnapshotCompare"
      data-part="compare"
      data-mode={@mode}
      style={@image.width && @image.height && "--snapshot-aspect: #{@image.width} / #{@image.height}"}
    >
      <div data-part="compare-frame">
        <img
          src={@src.(:baseline)}
          alt={dgettext("dashboard_snapshots", "Baseline")}
          data-part="compare-baseline"
          draggable="false"
        />
        <img
          src={@src.(:head)}
          alt={dgettext("dashboard_snapshots", "New")}
          data-part="compare-head"
          draggable="false"
        />
        <div :if={@mode == "wipe"} data-part="compare-handle"><span></span></div>
      </div>
      <input
        type="range"
        min="0"
        max="100"
        value="50"
        aria-label={
          if @mode == "wipe",
            do: dgettext("dashboard_snapshots", "Wipe position"),
            else: dgettext("dashboard_snapshots", "New image opacity")
        }
      />
      <div data-part="compare-legend">
        <span>{dgettext("dashboard_snapshots", "Baseline")}</span>
        <span>{dgettext("dashboard_snapshots", "New")}</span>
      </div>
    </div>
    """
  end

  def image_viewer(%{image: %{status: "changed"}, mode: "diff"} = assigns) do
    ~H"""
    <div data-part="panes">
      <figure data-part="pane">
        <figcaption>{dgettext("dashboard_snapshots", "Diff")}</figcaption>
        <img src={@src.(:diff)} alt={dgettext("dashboard_snapshots", "Diff")} />
      </figure>
    </div>
    """
  end

  def image_viewer(%{image: %{status: "changed"}} = assigns) do
    ~H"""
    <div data-part="panes">
      <figure data-part="pane">
        <figcaption>{dgettext("dashboard_snapshots", "Baseline")}</figcaption>
        <img src={@src.(:baseline)} alt={dgettext("dashboard_snapshots", "Baseline")} />
      </figure>
      <figure data-part="pane">
        <figcaption>{dgettext("dashboard_snapshots", "New")}</figcaption>
        <img src={@src.(:head)} alt={dgettext("dashboard_snapshots", "New")} />
      </figure>
    </div>
    """
  end

  def image_viewer(%{image: %{status: "removed"}} = assigns) do
    ~H"""
    <div data-part="panes">
      <figure data-part="pane">
        <figcaption>{dgettext("dashboard_snapshots", "Baseline")}</figcaption>
        <img src={@src.(:baseline)} alt={dgettext("dashboard_snapshots", "Baseline")} loading="lazy" />
      </figure>
    </div>
    """
  end

  def image_viewer(assigns) do
    ~H"""
    <div data-part="panes">
      <figure data-part="pane">
        <img src={@src.(:head)} alt={@image.name} loading="lazy" />
      </figure>
    </div>
    """
  end

  # Renamed and skipped images only appear in some builds, so their tabs do too.
  defp visible_statuses(counts),
    do: Enum.filter(@statuses, &(&1 not in ["renamed", "skipped"] or Map.get(counts, &1, 0) > 0))

  defp pull_request_label(%{pull_request_number: nil}), do: nil

  defp pull_request_label(%{pull_request_title: title, pull_request_number: number}) when is_binary(title),
    do: "##{number} · #{title}"

  defp pull_request_label(%{pull_request_number: number}), do: "##{number}"

  @doc "The pull request's page on the project's GitHub repository, when it has one connected."
  def pull_request_url(_project, nil), do: nil

  def pull_request_url(project, number), do: VCSLinks.pull_request_url(project, "refs/pull/#{number}/head")

  attr :label, :string, default: nil, doc: "The pull request's number and title, or nil without one."
  attr :url, :string, default: nil

  @doc """
  The Pull request field of a snapshot page's details: one line, cut with an
  ellipsis and shown whole on hover, linking to the pull request on GitHub.
  """
  def pull_request_metadata(assigns) do
    ~H"""
    <div data-part="metadata">
      <span data-part="title">{dgettext("dashboard_snapshots", "Pull request")}</span>
      <%= cond do %>
        <% is_nil(@label) -> %>
          <span data-part="label">{dgettext("dashboard_snapshots", "None")}</span>
        <% @url -> %>
          <a
            href={@url}
            target="_blank"
            rel="noopener noreferrer"
            data-part="label"
            data-truncate
            title={@label}
          >
            {@label}
          </a>
        <% true -> %>
          <span data-part="label" data-truncate title={@label}>{@label}</span>
      <% end %>
    </div>
    """
  end

  attr :id, :string, required: true
  attr :reviewer, :map, default: nil, doc: "From `reviewer/1`, or nil when nobody reviewed."
  slot :inner_block

  @doc """
  The review field of a snapshot page's details: who approved or rejected
  the changes and when, or that nobody has, so the details keep their shape.
  """
  def review_metadata(assigns) do
    ~H"""
    <div data-part="metadata">
      <%= if @reviewer do %>
        <span data-part="title">
          {if @reviewer.verdict == "rejected",
            do: dgettext("dashboard_snapshots", "Rejected"),
            else: dgettext("dashboard_snapshots", "Approved")}
        </span>
        <span data-part="reviewer">
          <.reviewer_avatar id={@id} reviewer={@reviewer} />
          <span data-part="label">{@reviewer.name} · {DateFormatter.from_now(@reviewer.at)}</span>
        </span>
      <% else %>
        <span data-part="title">{dgettext("dashboard_snapshots", "Review")}</span>
        <span data-part="label">{dgettext("dashboard_snapshots", "Not reviewed")}</span>
      <% end %>
      {render_slot(@inner_block)}
    </div>
    """
  end

  @doc """
  Who reviewed the build, with what verdict and when, for the avatars on the
  list and review pages: a Tuist account (its Gravatar) or a GitHub user who
  pressed the check run's button (their GitHub avatar). Nil without a review.
  """
  def reviewer(%{rejected_at: %DateTime{} = at} = build),
    do: reviewer_of(build.rejected_by_account, build.rejected_by_github_handle, "rejected", at)

  def reviewer(%{approved_at: %DateTime{} = at} = build),
    do: reviewer_of(build.approved_by_account, build.approved_by_github_handle, "approved", at)

  def reviewer(_build), do: nil

  defp reviewer_of(%Account{} = account, _handle, verdict, at) do
    image = with %User{} = user <- account.user, do: User.gravatar_url(user)
    %{name: account.name, image_href: image, color: Accounts.avatar_color(account), verdict: verdict, at: at}
  end

  defp reviewer_of(_account, handle, verdict, at) when is_binary(handle) do
    %{
      name: "@#{handle}",
      image_href: "https://github.com/#{URI.encode(handle)}.png?size=64",
      color: Accounts.avatar_color(%Account{name: handle}),
      verdict: verdict,
      at: at
    }
  end

  defp reviewer_of(_account, _handle, verdict, at),
    do: %{name: "?", image_href: nil, color: "gray", verdict: verdict, at: at}

  attr :id, :string, required: true
  attr :reviewer, :map, required: true

  def reviewer_avatar(assigns) do
    ~H"""
    <.avatar
      id={@id}
      name={@reviewer.name}
      image_href={@reviewer.image_href}
      color={@reviewer.color}
      size="2xsmall"
      title={@reviewer.name}
    />
    """
  end

  # An image is served through the build that uploaded it, which for a
  # commit's pooled images is not always the same one.
  def image_src(account, project, image, variant) do
    ~p"/#{account.name}/#{project.name}/snapshots/#{image.build_id}/images/#{image.id}/#{Atom.to_string(variant)}"
  end

  defp dimensions_changed?(image) do
    image.status == "changed" and not is_nil(image.baseline_width) and
      {image.width, image.height} != {image.baseline_width, image.baseline_height}
  end

  defp format_ratio(ratio) do
    percentage = ratio * 100
    if percentage < 0.01, do: "<0.01", else: :erlang.float_to_binary(percentage, decimals: 2)
  end

  @doc "An image's status against its baseline, worded and coloured for its badge."
  def status_label("changed"), do: dgettext("dashboard_snapshots", "Changed")
  def status_label("added"), do: dgettext("dashboard_snapshots", "Added")
  def status_label("removed"), do: dgettext("dashboard_snapshots", "Removed")
  def status_label("renamed"), do: dgettext("dashboard_snapshots", "Renamed")
  def status_label("skipped"), do: dgettext("dashboard_snapshots", "Skipped")
  def status_label("unchanged"), do: dgettext("dashboard_snapshots", "Unchanged")

  def status_color("changed"), do: "warning"
  def status_color("added"), do: "information"
  def status_color("removed"), do: "destructive"
  def status_color("renamed"), do: "information"
  def status_color(_), do: "neutral"

  defp mode_label("side_by_side"), do: dgettext("dashboard_snapshots", "Side by side")
  defp mode_label("diff"), do: dgettext("dashboard_snapshots", "Diff")
  defp mode_label("wipe"), do: dgettext("dashboard_snapshots", "Wipe")
  defp mode_label("onion"), do: dgettext("dashboard_snapshots", "Onion")

  attr :status, :string, required: true

  def verdict_badge(assigns) do
    ~H"""
    <.badge
      label={verdict_label(@status)}
      color={verdict_color(@status)}
      style="light-fill"
      size="large"
      data-part="status-badge"
    />
    """
  end

  def verdict_label("processing"), do: dgettext("dashboard_snapshots", "Processing")
  def verdict_label("failed"), do: dgettext("dashboard_snapshots", "Failed")
  def verdict_label("passed"), do: dgettext("dashboard_snapshots", "No changes")
  def verdict_label("baseline"), do: dgettext("dashboard_snapshots", "Baseline")
  def verdict_label("approved"), do: dgettext("dashboard_snapshots", "Approved")
  def verdict_label("rejected"), do: dgettext("dashboard_snapshots", "Rejected")
  def verdict_label("needs_review"), do: dgettext("dashboard_snapshots", "Needs review")

  defp verdict_color("passed"), do: "success"
  defp verdict_color("approved"), do: "success"
  defp verdict_color("needs_review"), do: "warning"
  defp verdict_color("failed"), do: "destructive"
  defp verdict_color("rejected"), do: "destructive"
  defp verdict_color(_), do: "neutral"
end
