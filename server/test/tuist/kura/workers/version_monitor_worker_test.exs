defmodule Tuist.Kura.Workers.VersionMonitorWorkerTest do
  use TuistTestSupport.Cases.DataCase, async: true

  import Mimic

  alias Tuist.Kura
  alias Tuist.Kura.Workers.VersionMonitorWorker

  setup :set_mimic_from_context

  test "schedules latest version deployments" do
    expect(Kura, :schedule_latest_version_deployments, fn -> {:ok, [%{id: "deployment-id"}]} end)

    assert :ok = VersionMonitorWorker.perform(%Oban.Job{})
  end

  test "returns an error when scheduling fails" do
    expect(Kura, :schedule_latest_version_deployments, fn -> {:error, :failed} end)

    assert {:error, :failed} = VersionMonitorWorker.perform(%Oban.Job{})
  end
end
