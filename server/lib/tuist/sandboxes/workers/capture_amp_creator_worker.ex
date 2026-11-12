defmodule Tuist.Sandboxes.Workers.CaptureAmpCreatorWorker do
  @moduledoc "Collects creator attribution without delaying or changing an Orb's lifecycle."
  use Oban.Worker,
    queue: :default,
    max_attempts: 5,
    unique: [keys: [:sandbox_id], states: [:available, :scheduled, :executing], period: :infinity]

  import Ecto.Query

  alias Tuist.OIDC
  alias Tuist.Repo
  alias Tuist.Sandboxes
  alias Tuist.Sandboxes.Sandbox

  @audience "https://tuist.dev"

  @impl Oban.Worker
  def perform(%Oban.Job{args: %{"sandbox_id" => id}}) do
    case Repo.get(Sandbox, id) do
      %Sandbox{amp_orb_id: "amp-" <> uuid, amp_creator_user_id: nil, state: :running} = sandbox ->
        capture(sandbox, "T-" <> uuid)

      _ ->
        :ok
    end
  end

  defp capture(sandbox, thread_id) do
    # The guest's existing Amp workload identity signs the proof. Never accept
    # arbitrary guest output as a user ID, persist the JWT, or log its output.
    command = ["amp", "orb", "id-token", "--audience", @audience]

    with {:ok, %{exit_code: 0, stdout: token}} <- Sandboxes.exec_running(sandbox, command, timeout_ms: 10_000),
         {:ok, %{thread_id: ^thread_id} = creator} <- OIDC.amp_creator(String.trim(token), @audience) do
      Repo.update_all(
        from(s in Sandbox, where: s.id == ^sandbox.id and is_nil(s.amp_creator_user_id)),
        set: [
          amp_creator_user_id: creator.user_id,
          amp_creator_username: creator.username,
          amp_creator_name: creator.name
        ]
      )

      :ok
    else
      _ -> {:error, :creator_unavailable}
    end
  end
end
