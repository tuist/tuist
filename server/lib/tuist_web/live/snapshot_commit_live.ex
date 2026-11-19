defmodule TuistWeb.SnapshotCommitLive do
  @moduledoc """
  A commit's snapshots, the page the Snapshots list opens: the images of every
  set, shard and rerun uploaded for the commit, pooled the way code coverage
  pools a commit's runs (`Tuist.Snapshots.commit_images/2`), reviewed
  together.
  """
  use TuistWeb, :live_view
  use Noora

  alias Tuist.Authorization
  alias Tuist.FeatureFlags
  alias Tuist.Snapshots
  alias Tuist.Snapshots.Commit
  alias Tuist.Utilities.DateFormatter
  alias TuistWeb.Authentication
  alias TuistWeb.Errors.NotFoundError
  alias TuistWeb.SnapshotBuildLive
  alias TuistWeb.SnapshotsLive
  alias TuistWeb.Utilities.SHA

  def mount(
        %{"git_commit_sha" => sha},
        _session,
        %{assigns: %{selected_project: project, selected_account: account}} = socket
      ) do
    if !FeatureFlags.snapshots_enabled?(account), do: raise(NotFoundError)

    user = Authentication.current_user(socket)

    {:ok,
     socket
     |> load_commit(sha)
     |> assign(
       :head_title,
       "#{SHA.format_commit_sha(sha)} · #{dgettext("dashboard_snapshots", "Snapshots")} · #{account.name}/#{project.name} · Tuist"
     )
     |> assign(:can_review, Authorization.authorize(:test_update, user, project) == :ok)}
  end

  defp load_commit(%{assigns: %{selected_project: project}} = socket, sha) do
    commit =
      case Snapshots.get_commit(project, sha) do
        {:ok, commit} -> commit
        {:error, :not_found} -> raise NotFoundError
      end

    project = Tuist.Repo.preload(project, vcs_connection: :github_app_installation)

    socket
    |> assign(:commit, commit)
    |> assign(:pull_request_url, SnapshotBuildLive.pull_request_url(project, commit.pull_request_number))
    |> assign(:builds, Snapshots.commit_builds(project, sha))
    |> assign(:images, Snapshots.commit_images(project, sha))
  end

  def handle_params(params, _uri, socket), do: {:noreply, assign_view(socket, params)}

  defp assign_view(%{assigns: %{commit: commit, images: images}} = socket, params) do
    set_name = if params["set"] in commit.set_names, do: params["set"]
    images = if set_name, do: Enum.filter(images, &(&1.set_name == set_name)), else: images

    socket
    |> assign(:params, params)
    |> assign(:set_name, set_name)
    |> assign(
      :review,
      SnapshotBuildLive.review_state(params, images, show_set: is_nil(set_name) and length(commit.set_names) > 1)
    )
  end

  def handle_event("search", %{"q" => search}, socket) do
    {:noreply, push_patch(socket, to: commit_query(socket.assigns, q: search), replace: true)}
  end

  def handle_event(event, _params, %{assigns: %{selected_project: project, commit: commit}} = socket)
      when event in ["approve", "reject"] do
    user = Authentication.current_user(socket)

    if Authorization.authorize(:test_update, user, project) == :ok do
      _ =
        if event == "approve",
          do: Snapshots.approve_commit(project, commit.git_commit_sha, user.account),
          else: Snapshots.reject_commit(project, commit.git_commit_sha, user.account)

      {:noreply, socket |> load_commit(commit.git_commit_sha) |> assign_view(socket.assigns.params)}
    else
      {:noreply, socket}
    end
  end

  # The review's query plus the page's own: the selected set.
  defp commit_query(assigns, overrides) do
    review = assigns.review

    query =
      [
        set: assigns.set_name,
        status: review.status,
        group: review.group,
        mode: review.mode,
        q: review.search,
        image: review.image
      ]
      |> Keyword.merge(overrides)
      |> Enum.reject(fn {_key, value} -> value in [nil, ""] end)

    "?" <> URI.encode_query(query)
  end

  def render(assigns) do
    ~H"""
    <div id="snapshot-commit">
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
          :if={@can_review and Enum.any?(@builds, &Snapshots.reviewable?(&1, @selected_project))}
          data-part="review-buttons"
        >
          <.button
            :if={@commit.status != "approved"}
            id="approve-snapshot-commit"
            label={dgettext("dashboard_snapshots", "Approve changes")}
            size="medium"
            phx-click="approve"
          >
            <:icon_left><.icon name="check" /></:icon_left>
          </.button>
          <.button
            :if={@commit.status != "rejected"}
            id="reject-snapshot-commit"
            label={dgettext("dashboard_snapshots", "Reject changes")}
            variant="destructive"
            size="medium"
            phx-click="reject"
          >
            <:icon_left><.icon name="close" /></:icon_left>
          </.button>
        </div>
      </div>

      <.card icon="git_commit" title={SnapshotsLive.commit_label(@commit)} data-part="details">
        <.card_section data-part="details-section">
          <div data-part="metadata-grid">
            <div data-part="metadata">
              <span data-part="title">{dgettext("dashboard_snapshots", "Status")}</span>
              <SnapshotBuildLive.verdict_badge status={@commit.status} />
            </div>
            <div data-part="metadata">
              <span data-part="title">{dgettext("dashboard_snapshots", "CI")}</span>
              <.badge
                id="snapshot-commit-completeness"
                label={SnapshotsLive.completeness_label(@commit)}
                color={if Commit.completeness(@commit) == :complete, do: "success", else: "neutral"}
                style="light-fill"
                size="large"
                title={SnapshotsLive.completeness_description(@commit)}
              />
            </div>
            <div data-part="metadata">
              <span data-part="title">{dgettext("dashboard_snapshots", "Branch")}</span>
              <span data-part="label">{@commit.git_branch || dgettext("dashboard_snapshots", "None")}</span>
            </div>
            <div data-part="metadata">
              <span data-part="title">{dgettext("dashboard_snapshots", "Commit SHA")}</span>
              <span data-part="label">{SHA.format_commit_sha(@commit.git_commit_sha)}</span>
            </div>
            <SnapshotBuildLive.pull_request_metadata
              label={@commit.pull_request_number && "##{@commit.pull_request_number}"}
              url={@pull_request_url}
            />
            <div data-part="metadata">
              <span data-part="title">{dgettext("dashboard_snapshots", "Compared with")}</span>
              <%= if @commit.baseline_commit_sha do %>
                <.link_button
                  navigate={
                    ~p"/#{@selected_account.name}/#{@selected_project.name}/snapshots/commits/#{@commit.baseline_commit_sha}"
                  }
                  label={SnapshotsLive.compared_with(@commit)}
                  variant="secondary"
                  size="medium"
                  underline
                />
              <% else %>
                <span data-part="label">{dgettext(
                  "dashboard_snapshots",
                  "Nothing, no earlier snapshots"
                )}</span>
              <% end %>
            </div>
            <SnapshotBuildLive.review_metadata
              id="snapshot-commit-reviewer"
              reviewer={SnapshotBuildLive.reviewer(@commit)}
            />
            <div data-part="metadata">
              <span data-part="title">{dgettext("dashboard_snapshots", "Last uploaded")}</span>
              <span data-part="label">{DateFormatter.from_now(@commit.last_uploaded_at)}</span>
            </div>
          </div>
        </.card_section>
      </.card>

      <SnapshotBuildLive.images_card
        review={@review}
        processing={@commit.status == "processing" and @review.counts == %{}}
        query={&commit_query(assigns, &1)}
        src={&SnapshotBuildLive.image_src(@selected_account, @selected_project, &1, &2)}
      >
        <:filters>
          <.dropdown
            :if={length(@commit.set_names) > 1}
            id="snapshot-commit-set"
            label={@set_name || dgettext("dashboard_snapshots", "All")}
            secondary_text={dgettext("dashboard_snapshots", "Set:")}
          >
            <.dropdown_item
              :for={set_name <- [nil | @commit.set_names]}
              value={set_name || "all"}
              label={set_name || dgettext("dashboard_snapshots", "All")}
              patch={commit_query(assigns, set: set_name, status: nil, group: nil, image: nil)}
              data-selected={@set_name == set_name}
            >
              <:right_icon :if={@set_name == set_name}><.check /></:right_icon>
            </.dropdown_item>
          </.dropdown>
        </:filters>
      </SnapshotBuildLive.images_card>
    </div>
    """
  end
end
