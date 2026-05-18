defmodule TuistWeb.TestCaseRunLive do
  @moduledoc false
  use TuistWeb, :live_view
  use Noora

  import TuistWeb.Components.EmptyTabStateBackground
  import TuistWeb.Helpers.AttachmentHelpers
  import TuistWeb.Helpers.FailureMessage
  import TuistWeb.Helpers.StackFrames
  import TuistWeb.Helpers.TestLabels
  import TuistWeb.Helpers.VCSLinks
  import TuistWeb.Runs.RanByBadge

  alias Tuist.Projects
  alias Tuist.Storage
  alias Tuist.Tests
  alias TuistWeb.Errors.NotFoundError
  alias TuistWeb.Utilities.Query

  # credo:disable-for-next-line Credo.Check.Refactor.CyclomaticComplexity
  def mount(params, _session, %{assigns: %{selected_project: project}} = socket) do
    test_case_run =
      case Tests.get_test_case_run_by_id(params["test_case_run_id"],
             project_id: project.id,
             preload: [
               :failures,
               :repetitions,
               :attachments,
               crash_report: :test_case_run_attachment,
               arguments: [:failures, :repetitions, :attachments]
             ]
           ) do
        {:ok, run} ->
          Tuist.Repo.preload(run, :ran_by_account)

        {:error, :not_found} ->
          raise NotFoundError, dgettext("dashboard_tests", "Test case run not found.")
      end

    if test_case_run.project_id != project.id do
      raise NotFoundError, dgettext("dashboard_tests", "Test case run not found.")
    end

    project = Tuist.Repo.preload(project, vcs_connection: :github_app_installation)

    slug = Projects.get_project_slug_from_id(project.id)

    test_run =
      case Tests.get_test(test_case_run.test_run_id) do
        {:ok, run} -> run
        {:error, :not_found} -> nil
      end

    test_case =
      if test_case_run.test_case_id do
        case Tests.get_test_case_by_id(test_case_run.test_case_id) do
          {:ok, tc} -> tc
          {:error, :not_found} -> nil
        end
      end

    flaky_run_group =
      if test_case_run.is_flaky and test_case_run.test_case_id do
        Tests.get_flaky_run_group_for_test_case_run(test_case_run)
      end

    socket =
      socket
      |> assign(:selected_project, project)
      |> assign(:test_case_run, test_case_run)
      |> assign(:test_run, test_run)
      |> assign(:test_case, test_case)
      |> assign(:flaky_run_group, flaky_run_group)
      |> assign(:head_title, "#{test_case_run.name} · #{slug} · Tuist")
      |> assign_text_attachment_urls(test_case_run)

    {:ok, socket}
  end

  def handle_params(_params, uri, socket) do
    params = Query.query_params(uri)
    uri = URI.new!("?" <> URI.encode_query(params))
    selected_tab = params["tab"] || "overview"

    socket =
      socket
      |> assign(:selected_tab, selected_tab)
      |> assign(:uri, uri)

    {:noreply, socket}
  end

  # Renders a failure message span without whitespace around the content.
  # Using ~H[] on a single line prevents the HEEx formatter from splitting
  # the tag across lines, which would introduce visible leading whitespace.
  attr :failure, :map, required: true
  attr :context, :map, required: true

  defp failure_message_span(assigns) do
    ~H[<span data-part="repetition-failure">{format_failure_message(@failure, @context)}</span>]
  end

  attr :attachment, :map, required: true
  attr :att_index, :any, required: true
  attr :project, :map, required: true
  attr :test_case_run, :map, required: true
  attr :text_attachment_urls, :map, required: true

  defp attachment_item(%{attachment: attachment} = assigns) do
    assigns = assign(assigns, :att_type, attachment_type(attachment.file_name))

    ~H"""
    <div
      :if={@att_type == :image}
      id={"attachment-#{@att_index}"}
      phx-hook="NooraCollapsible"
      data-part="collapsible"
      data-state="closed"
      class="test-failure-card"
    >
      <div data-part="root">
        <div data-part="trigger">
          <div data-part="header">
            <div data-part="icon">
              <.photo />
            </div>
            <div data-part="title-and-subtitle">
              <h3 data-part="title">{@attachment.file_name}</h3>
            </div>
            <.badge
              label={attachment_type_label(@att_type)}
              color="primary"
              style="light-fill"
              size="small"
            />
          </div>
          <.neutral_button
            href={
              ~p"/#{@project.account.name}/#{@project.name}/tests/test-cases/runs/#{@test_case_run.id}/attachments/#{@attachment.file_name}"
            }
            target="_blank"
            size="small"
          >
            <.download />
          </.neutral_button>
          <.neutral_button data-part="closed-collapsible-button" variant="secondary" size="small">
            <.chevron_down />
          </.neutral_button>
          <.neutral_button data-part="open-collapsible-button" variant="secondary" size="small">
            <.chevron_up />
          </.neutral_button>
        </div>
        <div data-part="content">
          <a
            href={
              ~p"/#{@project.account.name}/#{@project.name}/tests/test-cases/runs/#{@test_case_run.id}/attachments/#{@attachment.file_name}"
            }
            target="_blank"
          >
            <img
              src={
                ~p"/#{@project.account.name}/#{@project.name}/tests/test-cases/runs/#{@test_case_run.id}/attachments/#{@attachment.file_name}"
              }
              data-part="attachment-image"
              loading="lazy"
            />
          </a>
        </div>
      </div>
    </div>
    <div
      :if={text_attachment_type?(@att_type)}
      id={"text-attachment-#{@att_index}"}
      phx-hook="NooraCollapsible"
      data-part="collapsible"
      data-state="closed"
      class="test-failure-card"
    >
      <div data-part="root">
        <div data-part="trigger">
          <div data-part="header">
            <div data-part="icon">
              <.file_text />
            </div>
            <div data-part="title-and-subtitle">
              <h3 data-part="title">{@attachment.file_name}</h3>
            </div>
            <.badge
              label={attachment_type_label(@att_type)}
              color="primary"
              style="light-fill"
              size="small"
            />
          </div>
          <.neutral_button
            href={
              ~p"/#{@project.account.name}/#{@project.name}/tests/test-cases/runs/#{@test_case_run.id}/attachments/#{@attachment.file_name}"
            }
            target="_blank"
            size="small"
          >
            <.download />
          </.neutral_button>
          <.neutral_button data-part="closed-collapsible-button" variant="secondary" size="small">
            <.chevron_down />
          </.neutral_button>
          <.neutral_button data-part="open-collapsible-button" variant="secondary" size="small">
            <.chevron_up />
          </.neutral_button>
        </div>
        <div data-part="content">
          <div
            id={"text-attachment-content-#{@att_index}"}
            phx-hook="TextAttachmentContent"
            data-url={@text_attachment_urls[@attachment.id]}
          >
            <pre data-part="text-attachment-content">{dgettext("dashboard_tests", "Loading...")}</pre>
          </div>
        </div>
      </div>
    </div>
    <div
      :if={@att_type == :file}
      class="test-failure-card"
      data-part="collapsible"
    >
      <div data-part="root">
        <div data-part="trigger">
          <div data-part="header">
            <div data-part="icon">
              <.file />
            </div>
            <div data-part="title-and-subtitle">
              <h3 data-part="title">{@attachment.file_name}</h3>
            </div>
            <.badge
              label={attachment_type_label(:file)}
              color="primary"
              style="light-fill"
              size="small"
            />
          </div>
          <.neutral_button
            href={
              ~p"/#{@project.account.name}/#{@project.name}/tests/test-cases/runs/#{@test_case_run.id}/attachments/#{@attachment.file_name}"
            }
            target="_blank"
            size="small"
          >
            <.download />
          </.neutral_button>
        </div>
      </div>
    </div>
    """
  end

  defp has_repetition_attachments?(attachments) do
    Enum.any?(attachments, fn att ->
      attachment_type(att.file_name) != :ips and att.repetition_number != nil
    end)
  end

  defp group_attachments_by_repetition(attachments, repetitions) do
    visible_attachments =
      Enum.filter(attachments, fn att -> attachment_type(att.file_name) != :ips end)

    repetition_names =
      Map.new(repetitions, fn rep -> {rep.repetition_number, rep.name} end)

    {with_rep, without_rep} =
      Enum.split_with(visible_attachments, fn att -> att.repetition_number != nil end)

    grouped =
      with_rep
      |> Enum.group_by(& &1.repetition_number)
      |> Enum.sort_by(fn {rep_num, _} -> rep_num end)
      |> Enum.map(fn {rep_num, atts} ->
        name = Map.get(repetition_names, rep_num, "Attempt #{rep_num}")
        {rep_num, name, atts}
      end)

    {grouped, without_rep}
  end

  defp assign_text_attachment_urls(socket, test_case_run) do
    project = socket.assigns.selected_project

    all_attachments =
      test_case_run.attachments ++
        Enum.flat_map(test_case_run.arguments, & &1.attachments)

    urls =
      all_attachments
      |> Enum.filter(fn att -> text_attachment_type?(attachment_type(att.file_name)) end)
      |> Map.new(fn attachment ->
        s3_key =
          Tests.attachment_storage_key(%{
            account_handle: project.account.name,
            project_handle: project.name,
            test_run_id: attachment.test_run_id,
            test_case_run_id: test_case_run.id,
            attachment_id: attachment.id,
            file_name: attachment.file_name
          })

        {attachment.id, Storage.generate_download_url(s3_key, project.account, expires_in: 3600)}
      end)

    assign(socket, :text_attachment_urls, urls)
  end
end
