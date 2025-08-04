defmodule Tuist.QA.Workers.TestWorker do
  @moduledoc """
  A worker that adds a new Swift package and populates all its releases.
  """
  use Oban.Worker,
    unique: [
      period: :infinity,
      states: [:available, :scheduled, :executing, :retryable]
    ],
    max_attempts: 3

  alias Tuist.AppBuilds
  alias Tuist.QA

  @impl Oban.Worker
  def perform(%Oban.Job{args: %{"app_build_id" => app_build_id, "prompt" => prompt}} = _job) do
    {:ok, app_build} = AppBuilds.app_build_by_id(app_build_id, preload: [preview: [project: :account]])

    QA.test(%{app_build: app_build, prompt: prompt})
  end
end
