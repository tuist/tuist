defmodule Tuist.ObservabilityObanTest do
  use ExUnit.Case, async: true
  use Mimic

  alias Tuist.Accounts.Account
  alias Tuist.Builds.Workers.ProcessBuildWorker
  alias Tuist.Environment
  alias Tuist.FeatureFlags
  alias Tuist.Observability
  alias Tuist.Projects
  alias Tuist.Projects.Project
  alias Tuist.Storage

  setup :set_mimic_from_context

  test "loaded project context survives worker unwinding through the real Oban exception reporter" do
    parent = self()
    account = %Account{id: 42, name: "project-owner"}
    project = %Project{id: 99, account_id: 42, name: "app", account: account}
    stub(Environment, :error_tracking_enabled?, fn -> true end)
    stub(Environment, :env, fn -> :prod end)

    expect(Projects, :get_project_by_id, fn 99 -> project end)
    expect(FunWithFlags, :enabled?, fn :runners, [for: ^account] -> true end)

    expect(Storage, :download_to_file, fn _key, _path, ^account ->
      assert FeatureFlags.runners_enabled?(account)
      raise "download failed"
    end)

    expect(Sentry, :capture_exception, fn exception, opts ->
      event = Sentry.Event.create_event(Keyword.put(opts, :exception, exception))
      send(parent, {:reported, event})
      {:ok, "event"}
    end)

    args = %{build_id: "build", storage_key: "artifact", project_id: 99, account_id: 777}

    assert_raise RuntimeError, "download failed", fn ->
      Oban.Testing.perform_job(ProcessBuildWorker, args, repo: Tuist.Repo)
    end

    assert_receive {:reported, event}
    assert event.tags.selected_account_id == 42
    assert event.tags.selected_account_handle == "project-owner"
    assert event.tags.selected_project_id == 99
    assert event.tags["feature_flag.runners"] == "true"
    refute Map.has_key?(event.tags, :auth_account_id)

    # An unrelated job's actor-like arguments must neither establish a target
    # nor inherit the previous job's selected resource or evaluated decisions.
    unrelated = %Oban.Job{worker: "OtherWorker", queue: "default", args: %{"account_id" => 777}}
    :telemetry.execute([:oban, :job, :start], %{}, %{job: unrelated})
    assert Observability.snapshot().context.identity == %{}
    assert Sentry.Context.get_all().extra == %{}
    assert Sentry.Context.get_all().tags == %{}
    :telemetry.execute([:oban, :job, :stop], %{}, %{job: unrelated})
  end
end
