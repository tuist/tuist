defmodule Tuist.Sandboxes.Workers.CaptureAmpCreatorWorkerTest do
  use TuistTestSupport.Cases.DataCase, async: true
  use Mimic

  import TuistTestSupport.Fixtures.SandboxesFixtures

  alias Tuist.OIDC
  alias Tuist.Repo
  alias Tuist.Sandboxes
  alias Tuist.Sandboxes.Workers.CaptureAmpCreatorWorker

  test "captures a signed creator once without changing sandbox lifecycle" do
    uuid = Ecto.UUID.generate()
    sandbox = sandbox_fixture(amp_orb_id: "amp-" <> uuid)
    stub(Sandboxes, :exec_running, fn _, _, _ -> {:ok, %{exit_code: 0, stdout: "proof\n"}} end)

    stub(OIDC, :amp_creator, fn "proof", "https://tuist.dev" ->
      {:ok, %{user_id: "user_creator", name: "amp-name", username: "amp-name", thread_id: "T-" <> uuid}}
    end)

    assert :ok = perform_job(CaptureAmpCreatorWorker, %{sandbox_id: sandbox.id})

    assert %{
             amp_creator_user_id: "user_creator",
             amp_creator_username: "amp-name",
             amp_creator_name: "amp-name",
             state: :running
           } = Repo.reload!(sandbox)

    reject(&Sandboxes.exec_running/3)
    assert :ok = perform_job(CaptureAmpCreatorWorker, %{sandbox_id: sandbox.id})
  end

  test "does not trust another thread's proof and does not resume paused sandboxes" do
    sandbox = sandbox_fixture(amp_orb_id: "amp-" <> Ecto.UUID.generate())
    stub(Sandboxes, :exec_running, fn _, _, _ -> {:ok, %{exit_code: 0, stdout: "proof"}} end)

    stub(OIDC, :amp_creator, fn _, _ ->
      {:ok, %{user_id: "user_wrong", name: "wrong", thread_id: "T-" <> Ecto.UUID.generate()}}
    end)

    assert {:error, :creator_unavailable} = perform_job(CaptureAmpCreatorWorker, %{sandbox_id: sandbox.id})
    assert is_nil(Repo.reload!(sandbox).amp_creator_user_id)

    paused = sandbox_fixture(amp_orb_id: "amp-" <> Ecto.UUID.generate(), state: :paused)
    reject(&Sandboxes.exec_running/3)
    assert :ok = perform_job(CaptureAmpCreatorWorker, %{sandbox_id: paused.id})
  end
end
