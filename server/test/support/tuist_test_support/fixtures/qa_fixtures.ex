defmodule TuistTestSupport.Fixtures.QAFixtures do
  @moduledoc false

  alias Tuist.ClickHouseRepo
  alias Tuist.QA
  alias Tuist.QA.LaunchArgumentGroup
  alias Tuist.QA.Log
  alias Tuist.QA.Recording
  alias Tuist.QA.Screenshot
  alias Tuist.QA.Step
  alias Tuist.Repo
  alias TuistTestSupport.Fixtures.AppBuildsFixtures
  alias TuistTestSupport.Fixtures.ProjectsFixtures

  def qa_run_fixture(opts \\ []) do
    app_build =
      Keyword.get_lazy(opts, :app_build, fn ->
        project = Keyword.get(opts, :project)

        if project do
          AppBuildsFixtures.app_build_fixture(project: project)
        else
          AppBuildsFixtures.app_build_fixture()
        end
      end)

    {:ok, qa_run} =
      QA.create_qa_run(%{
        app_build_id: app_build.id,
        prompt: Keyword.get(opts, :prompt, "Test the login feature"),
        status: Keyword.get(opts, :status, "pending")
      })

    qa_run
  end

  def qa_step_fixture(opts \\ []) do
    qa_run =
      Keyword.get_lazy(opts, :qa_run, fn ->
        qa_run_fixture()
      end)

    %Step{}
    |> Step.changeset(%{
      qa_run_id: qa_run.id,
      action: Keyword.get(opts, :action, "Tap on Tuist label"),
      result: Keyword.get(opts, :result, "Detailed description of the test step"),
      issues: Keyword.get(opts, :issues, [])
    })
    |> Repo.insert!()
  end

  def screenshot_fixture(opts \\ []) do
    qa_run =
      Keyword.get_lazy(opts, :qa_run, fn ->
        qa_run_fixture()
      end)

    qa_step = Keyword.get(opts, :qa_step)

    %Screenshot{}
    |> Screenshot.changeset(%{
      qa_run_id: qa_run.id,
      qa_step_id: if(qa_step, do: qa_step.id)
    })
    |> Repo.insert!()
  end

  def qa_log_fixture(opts \\ []) do
    qa_run =
      Keyword.get_lazy(opts, :qa_run, fn ->
        qa_run_fixture()
      end)

    project = Repo.preload(qa_run.app_build, preview: [project: :account]).preview.project

    log_attrs = %{
      project_id: project.id,
      qa_run_id: qa_run.id,
      message: Keyword.get(opts, :message, "Test log message"),
      level: Keyword.get(opts, :level, "info"),
      timestamp: Keyword.get(opts, :timestamp, NaiveDateTime.utc_now()),
      inserted_at: NaiveDateTime.utc_now()
    }

    ClickHouseRepo.insert_stream("qa_logs", [log_attrs])

    struct(Log, log_attrs)
  end

  def launch_argument_group_fixture(opts \\ []) do
    project =
      Keyword.get_lazy(opts, :project, fn ->
        ProjectsFixtures.project_fixture()
      end)

    attrs = %{
      project_id: project.id,
      name: Keyword.get(opts, :name, "test-launch-args-#{TuistTestSupport.Utilities.unique_integer()}"),
      description: Keyword.get(opts, :description, "Test launch arguments group"),
      value: Keyword.get(opts, :value, "--test-flag value")
    }

    %LaunchArgumentGroup{}
    |> LaunchArgumentGroup.create_changeset(attrs)
    |> Repo.insert!()
  end

  def qa_recording_fixture(opts \\ []) do
    qa_run =
      Keyword.get_lazy(opts, :qa_run, fn ->
        qa_run_fixture()
      end)

    attrs = %{
      qa_run_id: qa_run.id,
      started_at: Keyword.get(opts, :started_at, DateTime.utc_now()),
      duration: Keyword.get(opts, :duration, 1500)
    }

    %Recording{}
    |> Recording.create_changeset(attrs)
    |> Repo.insert!()
  end
end
