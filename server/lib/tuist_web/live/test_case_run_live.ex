defmodule TuistWeb.TestCaseRunLive do
  @moduledoc false
  use TuistWeb, :live_view
  use Noora

  import TuistWeb.Components.EmptyTabStateBackground
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
             preload: [:failures, :repetitions, :attachments, crash_report: :test_case_run_attachment]
           ) do
        {:ok, run} ->
          Tuist.Repo.preload(run, :ran_by_account)

        {:error, :not_found} ->
          raise NotFoundError, dgettext("dashboard_tests", "Test case run not found.")
      end

    if test_case_run.project_id != project.id do
      raise NotFoundError, dgettext("dashboard_tests", "Test case run not found.")
    end

    project = Tuist.Repo.preload(project, :vcs_connection)

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

  def handle_params(params, _uri, socket) do
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

  defp attachment_type(file_name) do
    ext = file_name |> String.downcase() |> Path.extname()

    cond do
      ext in [".png", ".jpg", ".jpeg", ".gif", ".webp", ".heic"] -> :image
      ext in [".txt"] -> :text
      ext in [".log"] -> :log
      ext in [".json"] -> :json
      ext in [".xml"] -> :xml
      ext in [".csv"] -> :csv
      ext in [".ips"] -> :ips
      true -> :file
    end
  end

  defp text_attachment_type?(type), do: type in [:text, :log, :json, :xml, :csv]

  defp attachment_type_label(:image), do: dgettext("dashboard_tests", "Image")
  defp attachment_type_label(:text), do: dgettext("dashboard_tests", "Text File")
  defp attachment_type_label(:log), do: dgettext("dashboard_tests", "Log File")
  defp attachment_type_label(:json), do: "JSON"
  defp attachment_type_label(:xml), do: "XML"
  defp attachment_type_label(:csv), do: "CSV"
  defp attachment_type_label(:file), do: dgettext("dashboard_tests", "File")

  defp assign_text_attachment_urls(socket, test_case_run) do
    project = socket.assigns.selected_project

    urls =
      test_case_run.attachments
      |> Enum.filter(fn att -> text_attachment_type?(attachment_type(att.file_name)) end)
      |> Map.new(fn attachment ->
        s3_key =
          Tests.attachment_storage_key(%{
            account_handle: project.account.name,
            project_handle: project.name,
            test_case_run_id: test_case_run.id,
            attachment_id: attachment.id,
            file_name: attachment.file_name
          })

        {attachment.id, Storage.generate_download_url(s3_key, project.account, expires_in: 3600)}
      end)

    assign(socket, :text_attachment_urls, urls)
  end
end
