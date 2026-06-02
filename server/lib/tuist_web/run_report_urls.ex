defmodule TuistWeb.RunReportURLs do
  @moduledoc """
  Absolute URL builders for the entities referenced in the "Tuist Run Report".

  Shared by `Tuist.VCS.Workers.CommentWorker` (pull request comment) and
  `TuistWeb.API.AnalyticsController` (GitHub Actions job summary) so the links
  in both surfaces stay identical.
  """

  use Phoenix.VerifiedRoutes,
    endpoint: TuistWeb.Endpoint,
    router: TuistWeb.Router

  def preview_url(%{project: %{account: account} = project, preview: preview}) do
    url(~p"/#{account.name}/#{project.name}/previews/#{preview.id}")
  end

  def preview_qr_code_url(%{project: %{account: account} = project, preview: preview}) do
    url(~p"/#{account.name}/#{project.name}/previews/#{preview.id}/qr-code.png")
  end

  def test_run_url(%{project: %{account: account} = project, test_run: test_run}) do
    url(~p"/#{account.name}/#{project.name}/tests/test-runs/#{test_run.id}")
  end

  def bundle_url(%{project: %{account: account} = project, bundle: bundle}) do
    url(~p"/#{account.name}/#{project.name}/bundles/#{bundle.id}")
  end

  def build_url(%{project: %{account: account} = project, build: build}) do
    url(~p"/#{account.name}/#{project.name}/builds/build-runs/#{build.id}")
  end
end
