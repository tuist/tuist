defmodule Tuist.Sandboxes.Workers.CaptureAmpCreatorWorker do
  @moduledoc "Collects creator attribution without delaying or changing an Orb's lifecycle."
  use Oban.Worker,
    queue: :default,
    max_attempts: 20,
    unique: [keys: [:sandbox_id], states: [:available, :scheduled, :executing], period: :infinity]

  import Ecto.Query

  alias Tuist.OIDC
  alias Tuist.Repo
  alias Tuist.Sandboxes
  alias Tuist.Sandboxes.Sandbox

  @audience "https://tuist.dev"
  @identity_poll_seconds 60
  @identity_wait_limit_ms to_timeout(hour: 1)

  @impl Oban.Worker
  def perform(%Oban.Job{args: %{"sandbox_id" => id}} = job) do
    case Repo.get(Sandbox, id) do
      %Sandbox{amp_orb_id: "amp-" <> uuid, state: :running} = sandbox
      when is_nil(sandbox.amp_creator_user_id) or is_nil(sandbox.amp_creator_email) ->
        capture(sandbox, "T-" <> uuid, job)

      _ ->
        :ok
    end
  end

  # Keep trying while the Orb runs, without resuming it or delaying its startup.
  @impl Oban.Worker
  def backoff(_job), do: 60

  defp capture(sandbox, thread_id, job) do
    # The guest's existing Amp workload identity signs the proof. Never accept
    # arbitrary guest output as a user ID, persist the JWT, or log its output.
    # macOS bootstrap installs in ~/.amp/bin, outside the exec bridge's PATH.
    command = [
      "/bin/sh",
      "-c",
      ~S(export PATH="$HOME/.amp/bin:$PATH"; exec amp "$@"),
      "sh",
      "orb",
      "id-token",
      "--audience",
      @audience
    ]

    with {:ok, %{exit_code: 0, stdout: token}} <- Sandboxes.exec_running(sandbox, command, timeout_ms: 10_000),
         {:ok, creator} <- OIDC.amp_creator(String.trim(token), @audience),
         true <- creator.thread_id == thread_id do
      running_orb =
        from(s in Sandbox,
          where: s.id == ^sandbox.id and s.amp_orb_id == ^sandbox.amp_orb_id and s.state == :running
        )

      # Competing proofs can only capture the first creator. Email enrichment
      # independently checks that creator, never replacing their original labels.
      Repo.update_all(
        from(s in running_orb, where: is_nil(s.amp_creator_user_id)),
        set: [
          amp_creator_user_id: creator.user_id,
          amp_creator_username: creator.username,
          amp_creator_name: creator.name
        ]
      )

      if email = Map.get(creator, :email) do
        Repo.update_all(
          from(s in running_orb,
            where: s.amp_creator_user_id == ^creator.user_id and is_nil(s.amp_creator_email)
          ),
          set: [amp_creator_email: email]
        )
      end

      :ok
    else
      # Amp writes the Orb's workload identity minutes after boot, while its
      # detached setup runs; until then the command exits 1 with "No workload
      # identity request token is available". That wait is expected, so poll
      # without spending attempts or reporting each one as an error. Giving up
      # is reported once, since Oban does not report cancelled jobs.
      {:ok, %{exit_code: code}} when is_integer(code) ->
        if DateTime.diff(DateTime.utc_now(), job.inserted_at, :millisecond) < @identity_wait_limit_ms do
          {:snooze, @identity_poll_seconds}
        else
          Sentry.capture_message("Amp Orb never produced a creator identity token",
            level: :warning,
            extra: %{sandbox_id: sandbox.id, exit_code: code}
          )

          {:cancel, {:creator_command_failed, code}}
        end

      {:error, :invalid_token} ->
        {:error, :invalid_creator_proof}

      false ->
        {:error, :creator_thread_mismatch}

      _ ->
        {:error, :creator_unavailable}
    end
  end
end
