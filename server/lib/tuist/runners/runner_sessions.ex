defmodule Tuist.Runners.RunnerSessions do
  @moduledoc """
  Open/close the per-Pod billing record in Postgres.

  Two write paths:

    * **Open** — `open/1`, called from
      `Tuist.Runners.Jobs.record_claimed/3` at claim-win. Anchoring
      the open here (rather than on the controller's Pod-create
      event) keeps the warm pool's idle-poll time out of billing —
      a session only exists for Pods that actually claimed a
      customer workflow_job.

    * **Close** — `close_by_pod_name/2`, called from the
      runners-controller via `POST /api/internal/runners/pods/stopped`
      when the controller observes a Pod transition into a terminal
      phase. `ended_at` is K8s's
      `containerStatuses[runner].state.terminated.finishedAt` —
      the moment the container process actually exited.

  Both paths are fire-and-forget — they don't block the hot dispatch
  path and they swallow Postgres errors with a warning rather than
  failing the caller. A missed insert / update means we under-bill
  that customer for one Pod; a hard failure here would mean a
  missed claim or a missed controller report, which is much worse.
  Track failures via the warning log line; the operator should be
  alerted on sustained noise.

  ## Under-bill bias on re-emits

  Both writes are idempotent and biased so a duplicate delivery can
  never *extend* the billed window:

    * Re-emit on a still-open session → `started_at` becomes
      `MAX(existing, new)` (later start = shorter window).
    * Re-emit on an already-closed session → `ended_at` becomes
      `MIN(existing, new)` (earlier end = shorter window).

  Combined with the billing-query's `started_at + max_lifetime`
  safety clamp, the worst-case is "lost stopped event, session
  bills at most max_lifetime" — never "duplicate stopped event,
  session bills longer than it ran."
  """
  import Ecto.Query

  alias Tuist.Repo
  alias Tuist.Runners.RunnerSession

  require Logger

  @doc """
  Open a billing session once dispatch has committed (JIT
  minted + `running` recorded). `started_at` is the claim
  timestamp — the moment we bound the warm Pod to this
  workflow_job — which is a few hundred ms earlier than
  `running`. Opening at this point and not at claim-win is
  what makes failed dispatches leak-free: every call site is on
  the success branch of `Tuist.Runners.serve_claim/5`, after the
  with chain that can return `release_safely`.
  """
  def open(
        %{
          workflow_job_id: workflow_job_id,
          account_id: account_id,
          fleet_name: fleet_name,
          pod_name: pod_name,
          started_at: started_at
        } = attrs
      ) do
    now = DateTime.utc_now()

    attrs = %{
      workflow_job_id: workflow_job_id,
      account_id: account_id,
      fleet_name: fleet_name,
      pod_name: pod_name,
      runner_name: Map.get(attrs, :runner_name, ""),
      repository: Map.get(attrs, :repository, ""),
      workflow_name: Map.get(attrs, :workflow_name, ""),
      started_at: started_at,
      inserted_at: DateTime.truncate(now, :second),
      updated_at: DateTime.truncate(now, :second)
    }

    case Repo.insert(struct(RunnerSession, attrs)) do
      {:ok, session} ->
        {:ok, session}

      {:error, changeset} ->
        Logger.warning("runners: failed to open billing session",
          workflow_job_id: workflow_job_id,
          account_id: account_id,
          changeset_errors: inspect(changeset.errors)
        )

        {:error, changeset}
    end
  end

  @doc """
  Close the most recent open session for `pod_name` with the K8s-
  reported container termination time. Invoked when the
  runners-controller observes a Pod transition to a terminal
  phase.

  Under-bill bias:

    * No open session for that `pod_name` → `{:ok, :no_open_session}`
      (re-delivery of a stopped event after we already closed; or
      a stopped event for a Pod whose claim never landed —
      either way nothing to do, and silently ignoring is the
      right move under "under-bill rather than over-bill").
    * Session already has `ended_at` set → take `MIN(existing, new)`
      so a late-arriving event with a *later* timestamp can
      never extend the billed window.
    * Session is open → set `ended_at = new`.

  Returns `{:ok, session}` on success, `{:ok, :no_open_session}`
  when no open row matches, `{:error, changeset}` on persistence
  failure (logged with a warning before returning).
  """
  def close_by_pod_name(pod_name, %DateTime{} = ended_at) when is_binary(pod_name) and pod_name != "" do
    case latest_for_pod(pod_name) do
      nil ->
        {:ok, :no_open_session}

      %RunnerSession{} = session ->
        # Under-bill bias: if a previous close raced in with an
        # earlier timestamp, keep it. A late re-delivery with a
        # later `ended_at` should never extend the billed window.
        effective_end =
          case session.ended_at do
            nil -> ended_at
            %DateTime{} = existing -> earlier(existing, ended_at)
          end

        session
        |> Ecto.Changeset.cast(
          %{ended_at: effective_end, updated_at: DateTime.truncate(DateTime.utc_now(), :second)},
          [:ended_at, :updated_at]
        )
        |> Repo.update()
        |> case do
          {:ok, updated} ->
            {:ok, updated}

          {:error, changeset} ->
            Logger.warning("runners: failed to close billing session",
              pod_name: pod_name,
              changeset_errors: inspect(changeset.errors)
            )

            {:error, changeset}
        end
    end
  end

  defp latest_for_pod(pod_name) do
    # Prefer the open row if one exists; otherwise return whichever
    # closed row is most recent — the close path may need to clamp
    # its `ended_at` down on a duplicate delivery.
    open =
      RunnerSession
      |> where([s], s.pod_name == ^pod_name and is_nil(s.ended_at))
      |> order_by([s], desc: s.started_at)
      |> limit(1)
      |> Repo.one()

    open || most_recent_closed(pod_name)
  end

  defp most_recent_closed(pod_name) do
    RunnerSession
    |> where([s], s.pod_name == ^pod_name and not is_nil(s.ended_at))
    |> order_by([s], desc: s.started_at)
    |> limit(1)
    |> Repo.one()
  end

  defp earlier(%DateTime{} = a, %DateTime{} = b) do
    if DateTime.before?(a, b), do: a, else: b
  end
end
