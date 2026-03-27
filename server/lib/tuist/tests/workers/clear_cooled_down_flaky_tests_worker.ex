defmodule Tuist.Tests.Workers.ClearCooledDownFlakyTestsWorker do
  @moduledoc """
  A worker that clears cooled down flaky tests for a specific project.
  """
  use Oban.Worker

  alias Tuist.Projects
  alias Tuist.Tests

  @impl Oban.Worker
  def perform(%{args: %{"project_id" => project_id}}) do
    case Projects.get_project_by_id(project_id) do
      {:ok, project} -> Tests.clear_cooled_down_flaky_tests(project)
      {:error, :not_found} -> :ok
    end
  end
end
