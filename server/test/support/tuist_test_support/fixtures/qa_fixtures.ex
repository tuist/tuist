defmodule TuistTestSupport.Fixtures.QAFixtures do
  @moduledoc false

  alias Tuist.QA
  alias Tuist.QA.Screenshot
  alias Tuist.QA.Step
  alias Tuist.Repo
  alias TuistTestSupport.Fixtures.AppBuildsFixtures

  def qa_run_fixture(opts \\ []) do
    app_build =
      Keyword.get_lazy(opts, :app_build, fn ->
        AppBuildsFixtures.app_build_fixture()
      end)

    {:ok, qa_run} =
      QA.create_qa_run(%{
        app_build_id: app_build.id,
        prompt: Keyword.get(opts, :prompt, "Test the login feature"),
        status: Keyword.get(opts, :status, "pending"),
        summary: Keyword.get(opts, :summary, "Summary of the QA run")
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
      summary: Keyword.get(opts, :summary, "Completed login test step"),
      description: Keyword.get(opts, :description, "Detailed description of the test step"),
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
      qa_step_id: if(qa_step, do: qa_step.id, else: nil),
      file_name: Keyword.get(opts, :file_name, "screenshot"),
      title: Keyword.get(opts, :title, "Screenshot")
    })
    |> Repo.insert!()
  end
end
