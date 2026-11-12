defmodule Tuist.Sandboxes.Workers.CaptureAmpCreatorWorkerTest do
  use TuistTestSupport.Cases.DataCase, async: true
  use Mimic

  import TuistTestSupport.Fixtures.SandboxesFixtures

  alias Tuist.OIDC
  alias Tuist.Repo
  alias Tuist.Sandboxes
  alias Tuist.Sandboxes.Workers.CaptureAmpCreatorWorker

  @tag :tmp_dir
  test "captures a signed creator once with Amp outside the bridge's PATH", %{tmp_dir: home} do
    uuid = Ecto.UUID.generate()
    sandbox = sandbox_fixture(amp_orb_id: "amp-" <> uuid, platform: :darwin)
    amp = Path.join(home, ".amp/bin/amp")
    File.mkdir_p!(Path.dirname(amp))
    File.write!(amp, "#!/bin/sh\n[ \"$*\" = 'orb id-token --audience https://tuist.dev' ] || exit 1\nprintf 'proof\\n'\n")
    File.chmod!(amp, 0o755)

    stub(Sandboxes, :exec_running, fn _, command, _ ->
      {stdout, code} =
        System.cmd("/bin/sh", ["-c", ~S(exec "$@"), "sh" | command],
          env: [{"HOME", home}, {"PATH", "/usr/bin:/bin"}],
          stderr_to_stdout: true
        )

      {:ok, %{exit_code: code, stdout: stdout}}
    end)

    stub(OIDC, :amp_creator, fn "proof", "https://tuist.dev" ->
      {:ok,
       %{
         user_id: "user_creator",
         name: "amp-name",
         username: "amp-name",
         email: "creator@example.com",
         thread_id: "T-" <> uuid
       }}
    end)

    assert :ok = perform_job(CaptureAmpCreatorWorker, %{sandbox_id: sandbox.id})

    assert %{
             amp_creator_user_id: "user_creator",
             amp_creator_username: "amp-name",
             amp_creator_name: "amp-name",
             amp_creator_email: "creator@example.com",
             state: :running
           } = Repo.reload!(sandbox)

    reject(&Sandboxes.exec_running/3)
    assert :ok = perform_job(CaptureAmpCreatorWorker, %{sandbox_id: sandbox.id})
  end

  test "enriches the same creator's email without changing originally captured labels" do
    uuid = Ecto.UUID.generate()

    sandbox =
      [amp_orb_id: "amp-" <> uuid]
      |> sandbox_fixture()
      |> Ecto.Changeset.change(
        amp_creator_user_id: "user_creator",
        amp_creator_name: "original-name",
        amp_creator_username: "original-handle"
      )
      |> Repo.update!()

    stub(Sandboxes, :exec_running, fn _, _, _ -> {:ok, %{exit_code: 0, stdout: "proof"}} end)

    stub(OIDC, :amp_creator, fn _, _ ->
      {:ok,
       %{
         user_id: "user_creator",
         name: "new-name",
         username: "new-handle",
         email: "creator@example.com",
         thread_id: "T-" <> uuid
       }}
    end)

    assert :ok = perform_job(CaptureAmpCreatorWorker, %{sandbox_id: sandbox.id})

    assert %{
             amp_creator_user_id: "user_creator",
             amp_creator_name: "original-name",
             amp_creator_username: "original-handle",
             amp_creator_email: "creator@example.com"
           } = Repo.reload!(sandbox)
  end

  test "refuses another user's email even when the creator is captured while collecting the proof" do
    for already_captured <- [true, false] do
      uuid = Ecto.UUID.generate()
      sandbox = sandbox_fixture(amp_orb_id: "amp-" <> uuid)

      original_creator = [
        amp_creator_user_id: "user_original",
        amp_creator_name: "original-name",
        amp_creator_username: "original-handle"
      ]

      if already_captured, do: sandbox |> Ecto.Changeset.change(original_creator) |> Repo.update!()

      stub(Sandboxes, :exec_running, fn _, _, _ ->
        if !already_captured, do: sandbox |> Ecto.Changeset.change(original_creator) |> Repo.update!()
        {:ok, %{exit_code: 0, stdout: "proof"}}
      end)

      stub(OIDC, :amp_creator, fn _, _ ->
        {:ok,
         %{
           user_id: "user_other",
           name: "other-name",
           username: "other-handle",
           email: "other@example.com",
           thread_id: "T-" <> uuid
         }}
      end)

      assert :ok = perform_job(CaptureAmpCreatorWorker, %{sandbox_id: sandbox.id})

      assert %{
               amp_creator_user_id: "user_original",
               amp_creator_name: "original-name",
               amp_creator_username: "original-handle",
               amp_creator_email: nil
             } = Repo.reload!(sandbox)
    end
  end

  test "a stale proof cannot overwrite email captured while collecting it" do
    uuid = Ecto.UUID.generate()

    sandbox =
      [amp_orb_id: "amp-" <> uuid]
      |> sandbox_fixture()
      |> Ecto.Changeset.change(amp_creator_user_id: "user_creator", amp_creator_name: "original-name")
      |> Repo.update!()

    stub(Sandboxes, :exec_running, fn _, _, _ ->
      sandbox |> Ecto.Changeset.change(amp_creator_email: "first@example.com") |> Repo.update!()
      {:ok, %{exit_code: 0, stdout: "proof"}}
    end)

    stub(OIDC, :amp_creator, fn _, _ ->
      {:ok,
       %{
         user_id: "user_creator",
         name: "new-name",
         username: "new-handle",
         email: "later@example.com",
         thread_id: "T-" <> uuid
       }}
    end)

    assert :ok = perform_job(CaptureAmpCreatorWorker, %{sandbox_id: sandbox.id})

    assert %{
             amp_creator_user_id: "user_creator",
             amp_creator_name: "original-name",
             amp_creator_username: nil,
             amp_creator_email: "first@example.com"
           } = Repo.reload!(sandbox)
  end

  test "does not infer an email from the captured display label" do
    uuid = Ecto.UUID.generate()
    sandbox = sandbox_fixture(amp_orb_id: "amp-" <> uuid)
    stub(Sandboxes, :exec_running, fn _, _, _ -> {:ok, %{exit_code: 0, stdout: "proof"}} end)

    stub(OIDC, :amp_creator, fn _, _ ->
      {:ok, %{user_id: "user_creator", name: "creator@example.com", username: nil, email: nil, thread_id: "T-" <> uuid}}
    end)

    assert :ok = perform_job(CaptureAmpCreatorWorker, %{sandbox_id: sandbox.id})

    assert %{amp_creator_user_id: "user_creator", amp_creator_name: "creator@example.com", amp_creator_email: nil} =
             Repo.reload!(sandbox)
  end

  test "retries long enough to capture a creator after a slow detached setup" do
    uuid = Ecto.UUID.generate()
    sandbox = sandbox_fixture(amp_orb_id: "amp-" <> uuid)
    job = %{sandbox_id: sandbox.id} |> CaptureAmpCreatorWorker.new() |> Ecto.Changeset.apply_changes()

    stub(OIDC, :amp_creator, fn "proof", _ ->
      {:ok, %{user_id: "user_creator", name: "amp-name", username: nil, thread_id: "T-" <> uuid}}
    end)

    # The production setup that exposed this failure took 10 minutes 48 seconds.
    result =
      Enum.reduce_while(1..job.max_attempts, 0, fn attempt, elapsed ->
        stub(Sandboxes, :exec_running, fn _, _, _ ->
          if elapsed < 648,
            do: {:ok, %{exit_code: 1, stdout: "", stderr: "identity not ready"}},
            else: {:ok, %{exit_code: 0, stdout: "proof"}}
        end)

        case perform_job(CaptureAmpCreatorWorker, job.args, attempt: attempt) do
          :ok -> {:halt, :captured}
          {:error, _} -> {:cont, elapsed + CaptureAmpCreatorWorker.backoff(%{job | attempt: attempt})}
        end
      end)

    assert result == :captured
    assert %{amp_creator_user_id: "user_creator", state: :running} = Repo.reload!(sandbox)
  end

  test "reports failure stages without returning guest output" do
    sandbox = sandbox_fixture(amp_orb_id: "amp-" <> Ecto.UUID.generate())

    stub(Sandboxes, :exec_running, fn _, _, _ ->
      {:ok, %{exit_code: 1, stdout: "sensitive output", stderr: "sensitive error"}}
    end)

    assert {:error, {:creator_command_failed, 1}} =
             perform_job(CaptureAmpCreatorWorker, %{sandbox_id: sandbox.id})

    stub(Sandboxes, :exec_running, fn _, _, _ -> {:ok, %{exit_code: 0, stdout: "untrusted proof"}} end)
    stub(OIDC, :amp_creator, fn _, _ -> {:error, :invalid_token} end)
    assert {:error, :invalid_creator_proof} = perform_job(CaptureAmpCreatorWorker, %{sandbox_id: sandbox.id})
    assert is_nil(Repo.reload!(sandbox).amp_creator_user_id)
  end

  test "does not trust another thread's proof and does not resume paused sandboxes" do
    sandbox = sandbox_fixture(amp_orb_id: "amp-" <> Ecto.UUID.generate())
    stub(Sandboxes, :exec_running, fn _, _, _ -> {:ok, %{exit_code: 0, stdout: "proof"}} end)

    stub(OIDC, :amp_creator, fn _, _ ->
      {:ok, %{user_id: "user_wrong", name: "wrong", thread_id: "T-" <> Ecto.UUID.generate()}}
    end)

    assert {:error, :creator_thread_mismatch} = perform_job(CaptureAmpCreatorWorker, %{sandbox_id: sandbox.id})
    assert is_nil(Repo.reload!(sandbox).amp_creator_user_id)

    paused = sandbox_fixture(amp_orb_id: "amp-" <> Ecto.UUID.generate(), state: :paused)
    reject(&Sandboxes.exec_running/3)
    assert :ok = perform_job(CaptureAmpCreatorWorker, %{sandbox_id: paused.id})
  end
end
