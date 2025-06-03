defmodule TuistWeb.BuildRunLive do
  @moduledoc false
  use TuistWeb, :live_view
  use Noora

  import Phoenix.Component
  import TuistWeb.Runs.RanByBadge

  alias Tuist.Projects
  alias Tuist.Runs
  alias TuistWeb.Errors.NotFoundError
  alias TuistWeb.Utilities.Query

  def mount(params, _session, %{assigns: %{selected_project: project}} = socket) do
    run =
      case Runs.get_build(params["build_run_id"]) do
        nil ->
          raise NotFoundError, gettext("Build not found.")

        run ->
          run
      end

    slug = Projects.get_project_slug_from_id(project.id)

    run = run |> Tuist.Repo.preload([:project]) |> Tuist.ClickHouseRepo.preload([:issues])

    if run.project.id != project.id do
      raise NotFoundError, gettext("Build not found.")
    end

    socket =
      socket
      |> assign(:run, run)
      |> assign(:head_title, "#{gettext("Build Run")} · #{slug} · Tuist")
      |> assign(
        :warnings_grouped_by_path,
        run.issues |> Enum.filter(&(&1.type == "warning")) |> Enum.group_by(& &1.path)
      )
      |> assign(
        :errors_grouped_by_path,
        run.issues |> Enum.filter(&(&1.type == "error")) |> Enum.group_by(& &1.path)
      )

    {:ok, socket}
  end

  def handle_params(params, _uri, %{assigns: %{}} = socket) do
    uri =
      URI.new!(
        "?" <>
          URI.encode_query(
            Map.take(params, [
              "tab"
            ])
          )
      )

    socket =
      socket
      |> assign(:selected_tab, params["tab"] || "overview")
      |> assign(:uri, uri)

    {
      :noreply,
      socket
    }
  end

  attr :issues, :list, required: true
  attr :path, :string, required: true
  attr :run, :map, required: true
  attr :type, :string, required: true, values: ~w(error warning)

  def issue_card(assigns) do
    ~H"""
    <div
      id={"#{@path |> String.replace("/", "-")}-issue-collapsible"}
      phx-hook="NooraCollapsible"
      data-part="collapsible"
      data-state="closed"
      data-type={@type}
      class="issue-card"
    >
      <div data-part="root">
        <div data-part="trigger">
          <div data-part="header">
            <div data-part="icon">
              <%= if @type == "error" do %>
                <.alert_circle />
              <% else %>
                <.alert_hexagon />
              <% end %>
            </div>
            <div data-part="title-and-subtitle">
              <h3 data-part="title">
                {issue_title_for_type(hd(@issues), @run, @type)}
              </h3>
              <span :if={hd(@issues).target != "" || hd(@issues).project != ""} data-part="subtitle">
                {[hd(@issues).target, hd(@issues).project]
                |> Enum.filter(&(&1 != ""))
                |> Enum.join(" • ")}
              </span>
            </div>
            <.badge
              label={Enum.count(@issues)}
              color={if @type == "error", do: "destructive", else: "warning"}
              style="light-fill"
              size="small"
            />
          </div>
          <.neutral_button data-part="closed-collapsible-button" variant="secondary" size="small">
            <.chevron_down />
          </.neutral_button>
          <.neutral_button data-part="open-collapsible-button" variant="secondary" size="small">
            <.chevron_up />
          </.neutral_button>
        </div>
        <div data-part="content" data-state="closed" )>
          <%= for issue <- @issues do %>
            <span data-part="issue">
              {issue_message(issue, @run)}
            </span>
          <% end %>
        </div>
      </div>
    </div>
    """
  end

  defp issue_title(title, issue, run) do
    if not is_nil(issue.path) and String.contains?(title, issue.path) and
         not is_nil(run.project.vcs_repository_full_handle) and
         run.project.vcs_provider == :github and not is_nil(run.git_commit_sha) do
      title
      |> String.replace(
        issue.path,
        ~s(<a href="https://github.com/#{run.project.vcs_repository_full_handle}/blob/#{run.git_commit_sha}/#{issue.path}" target="_blank">#{issue.path}</a>)
      )
      |> raw()
    else
      title
    end
  end

  defp issue_message(issue, run) do
    if not is_nil(issue.path) and issue.path != "" and
         not is_nil(run.project.vcs_repository_full_handle) and
         run.project.vcs_provider == :github and not is_nil(run.git_commit_sha) do
      raw(
        gettext("%{message} in %{link}",
          message: issue.message,
          link:
            ~s(<a href="https://github.com/#{run.project.vcs_repository_full_handle}/blob/#{run.git_commit_sha}/#{issue.path}#L#{issue.starting_line}" target="_blank">#{issue.path}#L#{issue.starting_line}</a>)
        )
      )
    else
      issue.message
    end
  end

  # credo:disable-for-next-line Credo.Check.Refactor.CyclomaticComplexity
  defp issue_title_for_type(issue, run, type) do
    title =
      case {type, issue.step_type} do
        {"error", "c_compilation"} ->
          gettext("Failed compiling C file %{path}", path: issue.path)

        {"error", "swift_compilation"} ->
          gettext("Failed compiling Swift file %{path}", path: issue.path)

        {"error", "script_execution"} ->
          gettext("Failed executing script %{script_name}", script_name: issue.path)

        {"error", "create_static_library"} ->
          gettext("Failed creating static library %{path}", path: issue.path)

        {"error", "linker"} ->
          gettext("Failed linking %{path}", path: issue.path)

        {"error", "copy_swift_libs"} ->
          gettext("Failed copying Swift libraries %{path}", path: issue.path)

        {"error", "compile_assets_catalog"} ->
          gettext("Failed compiling assets catalog %{path}", path: issue.path)

        {"error", "compile_storyboard"} ->
          gettext("Failed compiling storyboard %{path}", path: issue.path)

        {"error", "write_auxiliary_file"} ->
          gettext("Failed writing auxiliary file %{path}", path: issue.path)

        {"error", "link_storyboards"} ->
          gettext("Failed linking storyboards %{path}", path: issue.path)

        {"error", "copy_resource_file"} ->
          gettext("Failed copying resource file %{path}", path: issue.path)

        {"error", "merge_swift_module"} ->
          gettext("Failed merging Swift module %{path}", path: issue.path)

        {"error", "xib_compilation"} ->
          gettext("Failed compiling XIB file %{path}", path: issue.path)

        {"error", "swift_aggregated_compilation"} ->
          gettext("Failed compiling Swift file %{path}", path: issue.path)

        {"error", "precompile_bridging_header"} ->
          gettext("Failed precompiling bridging header %{path}", path: issue.path)

        {"error", "validate_embedded_binary"} ->
          gettext("Failed validating embedded binary %{path}", path: issue.path)

        {"error", "validate"} ->
          gettext("Failed validating %{path}", path: issue.path)

        {"error", "other"} ->
          if is_nil(issue.path) or issue.path == "" do
            issue.title
          else
            gettext("Failed processing %{path}", path: issue.path)
          end

        {"warning", "c_compilation"} ->
          gettext("Warning when compiling C file %{path}", path: issue.path)

        {"warning", "swift_compilation"} ->
          gettext("Warning when compiling Swift file %{path}", path: issue.path)

        {"warning", "script_execution"} ->
          gettext("Warning when executing script %{script_name}", script_name: issue.path)

        {"warning", "create_static_library"} ->
          gettext("Warning when creating static library %{path}", path: issue.path)

        {"warning", "linker"} ->
          gettext("Warning when linking %{path}", path: issue.path)

        {"warning", "copy_swift_libs"} ->
          gettext("Warning when copying Swift libraries %{path}", path: issue.path)

        {"warning", "compile_assets_catalog"} ->
          gettext("Warning when compiling assets catalog %{path}", path: issue.path)

        {"warning", "compile_storyboard"} ->
          gettext("Warning when compiling storyboard %{path}", path: issue.path)

        {"warning", "write_auxiliary_file"} ->
          gettext("Warning when writing auxiliary file %{path}", path: issue.path)

        {"warning", "link_storyboards"} ->
          gettext("Warning when linking storyboards %{path}", path: issue.path)

        {"warning", "copy_resource_file"} ->
          gettext("Warning when copying resource file %{path}", path: issue.path)

        {"warning", "merge_swift_module"} ->
          gettext("Warning when merging Swift module %{path}", path: issue.path)

        {"warning", "xib_compilation"} ->
          gettext("Warning when compiling XIB file %{path}", path: issue.path)

        {"warning", "swift_aggregated_compilation"} ->
          gettext("Warning when compiling Swift file %{path}", path: issue.path)

        {"warning", "precompile_bridging_header"} ->
          gettext("Warning when precompiling bridging header %{path}", path: issue.path)

        {"warning", "validate_embedded_binary"} ->
          gettext("Warning when validating embedded binary %{path}", path: issue.path)

        {"warning", "validate"} ->
          gettext("Warning when validating %{path}", path: issue.path)

        {"warning", "other"} ->
          if is_nil(issue.path) or issue.path == "" do
            issue.title
          else
            gettext("Warning when processing %{path}", path: issue.path)
          end
      end

    issue_title(title, issue, run)
  end
end
