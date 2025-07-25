defmodule TuistTestSupport.Fixtures.QAFixtures do
  @moduledoc false

  alias Tuist.QA
  alias Tuist.QA.Run
  alias Tuist.QA.RunStep
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
        status: Keyword.get(opts, :status, "pending")
      })

    qa_run
  end

  def qa_run_step_fixture(opts \\ []) do
    qa_run =
      Keyword.get_lazy(opts, :qa_run, fn ->
        qa_run_fixture()
      end)

    %RunStep{}
    |> RunStep.changeset(%{
      qa_run_id: qa_run.id,
      summary: Keyword.get(opts, :summary, "Completed login test step")
    })
    |> Repo.insert!()
  end
end
