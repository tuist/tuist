defmodule Tuist.Runners.Workers.OrphanedRunnersWorker do
  @moduledoc """
  Recovers workflow_job lifecycle rows the server transitioned to
  `status = 'running'` but whose GitHub Actions runner never
  actually came up.

  ## What "orphaned running" means

  Happy path:

      Pod polls → server claims → mints JIT → returns 200 to Pod
        → row: status='running', PG claim: lifecycle_state='running'
      Pod execs ./run.sh --jitconfig <JIT>
        → runner registers with GitHub, accepts the workflow_job
        → GitHub fires workflow_job.in_progress
      Job runs → ./run.sh exits → Pod halts → tart-kubelet flips
        to Succeeded → reconciler reaps + boots replacement
      GitHub fires workflow_job.completed → server marks row
        completed, frees PG cap slot

  Failure path this worker catches:

      Pod polls → server claims → mints JIT → returns 200 to Pod
        → row: status='running'
      Pod's tart-kubelet on a degraded node never starts the
        container; OR the runner agent crashes before registering;
        OR network from VM to github.com is broken
        → runner NEVER registers with GitHub
        → no workflow_job.in_progress webhook ever arrives
        → row stays status='running' forever; PG cap slot
          consumed forever; workflow_job stays 'queued' on GitHub
          forever (no runner matched it)
        → customer eventually times out the workflow and ships
          a bug report

  `StaleClaimsWorker` doesn't catch this case: it intentionally
  excludes `lifecycle_state='running'` rows because a real running
  build holds the slot for as long as the build takes (potentially
  hours), and reaping at the 5-min threshold would free the slot
  of an actively-running runner. The signal that distinguishes
  "real running build" from "orphaned mint" is the GitHub-side
  status of the workflow_job — if GH still reports `queued` after
  we've supposedly transitioned through `claimed → running`, the
  runner never registered.

  ## How it works

    1. List lifecycle rows in `status='running'` with
       `started_at < now - @stale_after_seconds`.
    2. For each, call `GET /repos/{owner}/{repo}/actions/jobs/{id}`
       on the org's GitHub App installation.
    3. If GH returns `status: 'queued'` with no runner assigned, the
       runner may never have come up, unless the claim records an
       execution or its Pod, still present, reports that its runner was
       started: then the Pod is busy, GitHub is lagging, and the row is
       left alone. Otherwise schedule a confirmation for the
       same claim a grace period later (see "Confirming `queued`"), and
       only if GitHub still says `queued` then, recover via
       `Claims.release/2` (with the original `claimed_at` as the
       handle), which deletes the claim and re-queues the lifecycle
       row in one transaction.
    4. If GH returns `status: 'in_progress'` → runner is actually
       running; leave the row alone.
    5. If GH returns `status: 'completed'` → GH has a terminal
       state but we missed the webhook; mark the job completed and
       free the claim.
    6. Any other return / API failure → log and retry next tick.

  ## Threshold

  5 min is the same threshold `StaleClaimsWorker` uses for
  `claimed`. The happy path from mint to runner-registers-with-GH
  is sub-30s in practice (Pod-side: receive JIT → exec run.sh →
  agent registers → GH dispatches the workflow_job); 5 min is a
  generous floor that won't false-positive a slow boot.

  It is a floor on *asking*, not on acting, and it is only needed
  while the Pod is still there — the sweep cannot tell a booting
  runner from a dead one without GitHub's answer, and paying a GitHub
  call per `running` row per minute to find out is what the floor
  buys off. Once the Pod is gone the ambiguity is gone with it, so the
  pod-gone arm below skips the wait. Cutting the floor itself would
  trade directly against cold-boot time, which is why it stays where
  it is now that the arm covers the case it was costing.

  ## Pod-gone arm

  The push signal that a Pod stopped (`pods/stopped` →
  `OrphanedRunnersWorker` in targeted mode) is the fast path, but it
  rides a best-effort billing endpoint: a dropped POST, a controller
  restart mid-reap, or a Pod removed by node loss, eviction or drain
  rather than by the reap all leave nothing behind, and the customer
  waits out the floor plus up to a full cron period of phase
  misalignment on top.

  So the same question is also asked level-triggered, off one cluster
  read per tick: is the Pod bound to this `running` row still there?
  Age decides which rows are candidates; absence decides what evidence
  each candidate carries. Keeping those two separate is load-bearing: a
  row that crosses the floor before the first successful read would
  otherwise be filed under age for the rest of its life and never regain
  the absence that settles the busy guard below.
  Absence widens what is asked about, never what is acted on — every
  candidate still goes through the GitHub cross-check — and any read
  that fails or comes back empty narrows straight back to the age
  gate.

  Absence also settles the `executing?/1` busy guard in the queued
  branch, which is why the evidence is threaded through rather than
  just used to pick candidates. That guard holds a claim recording an
  execution because the runner is presumed hard at work on a sibling's
  job. A Pod that is gone is not, and since GitHub binds a JIT runner
  by label set, executing a sibling's job is the *common* shape — so
  leaving the guard in force would send precisely the population this
  arm exists for back to `PodReconciliationWorker`'s 10-minute grace
  plus 5-minute confirmation. The release stays handle-guarded on
  `claimed_at`, so a row a replacement Pod has since re-claimed is
  still untouchable.

  ## Targeted mode

  The threshold exists because the sweep cannot distinguish a
  healthy in-flight build from an orphan without asking GitHub, and
  a `running` row is overwhelmingly the former. That reasoning does
  not apply once we have direct evidence the Pod is gone: the
  controller's `pods/stopped` report releases the claim and passes
  the released job here as
  `%{"workflow_job_id" => id, "pod_name" => name}`, which re-checks
  that one job immediately.

  Both keys are load-bearing. The Pod name binds the run to the
  attempt that actually stopped, because a queued Oban job can be
  delayed past a re-queue and a fresh claim. Recovering the row
  then would release the *replacement's* claim: GitHub still
  reports `queued` while the new runner registers, and the
  stale-handle guard in `Claims.release/2` does not catch it either,
  since re-reading the row hands us the replacement's `claimed_at`
  rather than the stale one the sweep would have been holding.

  Without it the released job is stranded for the full 5 minutes.
  Releasing the PG claim does not make the job dispatchable — the
  ClickHouse row is still `running` and `pick_queued/2` skips it —
  and GitHub never re-announces a job it still considers `queued`,
  so nothing else moves it. The customer sees "waiting for a
  runner" for that whole window with warm capacity sitting idle.

  Targeted mode is the same recovery with the same GitHub
  cross-check, so the safety story is unchanged; only the age gate
  is skipped. It also carries `:pod_stopped`, which settles the
  `executing?/1` busy guard described under the pod-gone arm. That
  used to be satisfied only as a side effect of the caller having
  deleted the claim first, which made a correctness path depend on
  one release winning a race it is not guaranteed to win.

  ## Confirming `queued`

  GitHub's job API is eventually consistent. A job can read `queued`
  for tens of seconds after a runner has picked it up, and even after
  that runner has finished it and exited. The pod-gone arm and targeted
  mode ask within a second of the Pod stopping, which is exactly when a
  short job's read is most likely to lag, and re-queueing on that read
  sends a second runner after a job that already ran.

  So a `queued` answer is acted on only when it holds across
  `@queued_confirm_after_seconds`. The first sighting schedules a
  confirmation bound to the claim's `claimed_at`. That run re-reads
  the row, does nothing unless it is still `running` under the same
  claim, and asks GitHub again. A job GitHub has already assigned
  reports a `runner_name` even while its status still lags, so that
  alone reads as `in_progress`.

  Only GitHub answers are gated. Buildkite and GitLab report their own
  job state and keep acting on the first answer.

  ## Cost

  One GitHub API call per orphaned candidate per tick, plus a second
  one only for candidates GitHub reports as `queued`, which is the
  branch that resolves the parent run. Confirming a `queued` answer
  repeats both calls once per claim. A real in-flight build reports
  `in_progress` and never pays the second call, so in steady state the
  run lookups are a handful per hour: they track the orphan rate, not
  the build rate.

  The bound that matters is the pathological one, where every candidate
  reports `queued` (mass dispatch failure, or GitHub degraded) and the
  rate doubles. Candidates are capped by concurrent `running` rows, and
  the observed peak across all fleets is ~30, so the ceiling is ~60
  calls/min ≈ 3,600/hr. That fits inside the 5,000/hr app-token limit,
  which is per installation and therefore per account: `recover_one/2`
  resolves each orphan's own installation, so no account's fleet can
  spend another's budget.

  Headroom is not unlimited. `Tuist.GitHub.Retry` retries `429` up to
  three times, so sustained secondary-limit pressure multiplies calls
  rather than shedding them. If concurrency per account grows well past
  the current peak, gate the run lookup on the row's age: a genuine
  strand clears in one re-queue, so only a job that keeps coming back
  needs its run resolved.
  """

  use Oban.Worker, queue: :default, max_attempts: 1

  alias Tuist.Accounts
  alias Tuist.Environment
  alias Tuist.GitHub.Client, as: GitHubClient
  alias Tuist.Kubernetes.Client, as: K8sClient
  alias Tuist.Runners.Buildkite
  alias Tuist.Runners.Claims
  alias Tuist.Runners.GitLab
  alias Tuist.Runners.Jobs
  alias Tuist.Runners.Telemetry
  alias Tuist.Runners.WorkflowJobs
  alias Tuist.VCS

  require Logger

  @stale_after_seconds 300
  @queued_confirm_after_seconds 60
  @runner_label_selector "tuist.dev/runner=true"
  @runner_heartbeat_state_annotation "tuist.dev/runner-heartbeat-state"
  @runner_heartbeat_claimed "claimed"
  @evidence_by_arg %{"pod_stopped" => :pod_stopped, "aged_out" => :aged_out}

  @impl Oban.Worker
  def perform(%Oban.Job{
        args: %{"workflow_job_id" => workflow_job_id, "confirm_claimed_at" => claimed_at, "evidence" => evidence}
      })
      when is_integer(workflow_job_id) and is_map_key(@evidence_by_arg, evidence) do
    # A row that left `running`, most often because the `completed`
    # webhook GitHub's lagging read was hiding has landed, or that was
    # re-claimed under a new handle, is not the claim we saw.
    with {:ok, claimed_at, _offset} <- DateTime.from_iso8601(claimed_at),
         %{claimed_at: %DateTime{} = current_claimed_at} = orphan <- Jobs.get_orphaned_running(workflow_job_id),
         :eq <- DateTime.compare(current_claimed_at, claimed_at) do
      recover_one(orphan, Map.fetch!(@evidence_by_arg, evidence), :confirmation)
    end

    :ok
  end

  def perform(%Oban.Job{args: %{"workflow_job_id" => workflow_job_id, "pod_name" => pod_name}})
      when is_integer(workflow_job_id) and is_binary(pod_name) and pod_name != "" do
    case Jobs.get_orphaned_running(workflow_job_id) do
      nil ->
        # The row moved on between the release and this run: the
        # executor's `completed` webhook landed, or the job was
        # re-queued. Either way there is nothing orphaned.
        :ok

      %{pod_name: ^pod_name} = orphan ->
        recover_one(orphan, :pod_stopped)
        :ok

      %{pod_name: current_pod} ->
        # The row is `running` again, but for a DIFFERENT Pod: the job
        # was re-queued and re-claimed while this run sat in the queue.
        # Recovering it here would release the replacement's claim using
        # the replacement's own `claimed_at` — GitHub still reports
        # `queued` while its runner registers, so the GH check does not
        # save us, and the stale-handle guard in `Claims.release/2`
        # cannot either, because re-reading the row hands us the new
        # handle rather than the old one. Only the Pod we were told
        # stopped is ours to act on.
        Logger.info("runners: targeted orphan recovery skipped — job re-claimed by another pod",
          workflow_job_id: workflow_job_id,
          stopped_pod: pod_name,
          current_pod: current_pod
        )

        :ok
    end
  end

  def perform(%Oban.Job{args: %{"workflow_job_id" => workflow_job_id}}) do
    # Targeted recovery is only safe when it can prove the row still
    # belongs to the attempt that stopped, so a job without the Pod
    # binding is dropped rather than run unbound or widened into a full
    # sweep. The 1-minute sweep still covers the row.
    Logger.warning("runners: targeted orphan recovery missing pod_name; leaving it to the sweep",
      workflow_job_id: workflow_job_id
    )

    :ok
  end

  def perform(_job) do
    threshold = DateTime.add(DateTime.utc_now(), -@stale_after_seconds, :second)

    recovered =
      threshold
      |> candidates()
      |> Enum.filter(fn {orphan, evidence} -> recover_one(orphan, evidence) end)
      |> Enum.frequencies_by(fn {_orphan, evidence} -> evidence end)

    aged_out = Map.get(recovered, :aged_out, 0)
    pod_gone = Map.get(recovered, :pod_stopped, 0)

    if aged_out + pod_gone > 0 do
      Logger.warning("runners: rescued orphaned running rows",
        count: aged_out + pod_gone,
        aged_out: aged_out,
        pod_gone: pod_gone,
        stale_after_seconds: @stale_after_seconds
      )
    end

    :ok
  end

  # `{orphan, evidence}` pairs for everything worth asking the provider about.
  #
  # The floor is a stand-in for evidence: the sweep cannot tell a healthy
  # in-flight build from an orphan without asking GitHub, so it waits 5
  # minutes before asking. A Pod that is gone is that evidence directly.
  # `pods/stopped` carries it sooner, but only as a push on a best-effort
  # billing path — a dropped POST, a controller restart mid-reap, or a Pod
  # removed by node loss, eviction or drain rather than by the reap all
  # leave nothing behind. This asks the same question level-triggered, so
  # the answer does not depend on how we learned.
  #
  # Absence widens what is asked about, never what is acted on:
  # `recover_one/2` still cross-checks GitHub before re-queueing.
  defp candidates(threshold) do
    case {Jobs.list_orphaned_running(threshold), Jobs.list_running_since(threshold)} do
      # Nothing running, no cluster read — steady state costs two queries.
      {[], []} -> []
      {aged, recent} -> tag_evidence(aged, recent)
    end
  end

  defp tag_evidence(aged, recent) do
    observed = observed_pod_names()

    # An aged row is a candidate on age alone; absence, where the read
    # proves it, is the stronger evidence and outranks age. Evaluating it
    # here rather than only for `recent` is what stops a row that aged
    # past the floor from losing that evidence permanently.
    aged_candidates = Enum.map(aged, &{&1, evidence(&1, observed)})

    # A row inside the floor is a candidate only once its Pod is gone. The
    # floor still owns "Pod present but the runner never registered".
    recent_candidates =
      recent
      |> Enum.filter(&pod_gone?(&1, observed))
      |> Enum.map(&{&1, :pod_stopped})

    aged_candidates ++ recent_candidates
  end

  defp evidence(orphan, observed) do
    if pod_gone?(orphan, observed), do: :pod_stopped, else: :aged_out
  end

  defp pod_gone?(%{pod_name: pod_name}, {:ok, observed}) do
    # A blank name matches no Pod, so it would read as absent
    # unconditionally. Every `running` row carries the Pod that minted
    # it; anything else is not ours to recover on this signal.
    is_binary(pod_name) and pod_name != "" and not MapSet.member?(observed, pod_name)
  end

  defp pod_gone?(_candidate, :error), do: false

  defp observed_pod_names do
    case K8sClient.list_pods(Environment.runners_namespace(), @runner_label_selector) do
      {:ok, items} ->
        observed =
          items
          |> Enum.map(&get_in(&1, ["metadata", "name"]))
          |> Enum.reject(&is_nil/1)
          |> MapSet.new()

        if MapSet.size(observed) == 0 do
          # Rows are running, so the fleet cannot really be empty: a
          # wrong selector or an empty page reads the same as every Pod
          # vanishing at once. Narrow back to the age gate.
          Logger.error("runners: orphan sweep read no Pods while rows are running; skipping the pod-gone arm")

          :error
        else
          {:ok, observed}
        end

      {:error, reason} ->
        Logger.warning("runners: orphan sweep cluster read failed; skipping the pod-gone arm",
          reason: inspect(reason)
        )

        :error
    end
  end

  # `evidence` is what the caller knows about the Pod behind the claim:
  # `:pod_stopped` when it has been observed gone (reported stopped, or
  # absent from the cluster read), `:aged_out` when the row's age is all
  # there is to go on — including when the read failed, so a read we
  # could not trust degrades to the old behaviour rather than to a
  # guess. Only the queued branch reads it.
  # A Buildkite row cannot be asked about on GitHub: its surrogate id is
  # unknown there, and the 404 would read as "pruned" and complete a job
  # that may still be running. Buildkite's own answer arrives folded into
  # the vocabulary the GitHub branch acts on.
  #
  # `stage` is `:confirmation` when this run is the scheduled re-check of
  # a `queued` GitHub answer, and `:first_sighting` otherwise.
  defp recover_one(orphan, evidence, stage \\ :first_sighting)

  defp recover_one(%{provider: "gitlab", account_id: account_id} = orphan, evidence, _stage) do
    with {:ok, account} <- Accounts.get_account_by_id(account_id),
         {:ok, {status, conclusion}} <- GitLab.orphan_status(orphan, evidence) do
      handle_gh_status(status, conclusion, orphan, account, evidence, :confirmation)
    else
      _ -> false
    end
  end

  defp recover_one(
         %{provider: "buildkite", workflow_job_id: workflow_job_id, account_id: account_id} = orphan,
         evidence,
         _stage
       ) do
    with {:ok, account} <- Accounts.get_account_by_id(account_id),
         {:ok, {status, conclusion}} <- Buildkite.orphan_status(orphan) do
      handle_gh_status(status, conclusion, orphan, account, evidence, :confirmation)
    else
      {:error, reason} ->
        Logger.warning("runners: orphan worker buildkite lookup failed; will retry next tick",
          workflow_job_id: workflow_job_id,
          reason: inspect(reason)
        )

        false
    end
  end

  defp recover_one(
         %{workflow_job_id: workflow_job_id, account_id: account_id, repository: repository} = orphan,
         evidence,
         stage
       ) do
    with {:ok, account} <- Accounts.get_account_by_id(account_id),
         {:ok, installation} <- VCS.get_github_app_installation_for_account(account.id) do
      case GitHubClient.get_workflow_job(installation, repository, workflow_job_id) do
        {:ok, job} ->
          {gh_status, conclusion} = effective_gh_status(installation, orphan, job)
          handle_gh_status(gh_status, conclusion, orphan, account, evidence, stage)

        {:error, :not_found} ->
          # GH pruned the workflow_job (90-day retention by default).
          # The job can't be live; treat as completed so the PG cap
          # slot doesn't leak forever.
          handle_gh_status("completed", "", orphan, account, evidence, stage)

        {:error, reason} ->
          Logger.warning("runners: orphan worker GH lookup failed; will retry next tick",
            workflow_job_id: workflow_job_id,
            reason: inspect(reason)
          )

          false
      end
    else
      {:error, :not_found} ->
        # Account row gone (rare). Leave the orphan; cap accounting
        # is moot if the account itself is deleted.
        false
    end
  end

  # `queued` on the per-job endpoint does not mean the job is still
  # dispatchable. A run that has already reached `completed`, most often
  # via `startup_failure`, which skips every sibling job and leaves one
  # behind, never assigns its remaining jobs, yet GitHub keeps reporting
  # them as `queued` indefinitely. Re-queueing on the job's status alone puts such
  # a job back at the head of the fleet queue (dispatch orders by oldest
  # `enqueued_at`), where the next Pod claims it, strands, and lands here
  # again every tick. Resolving the run turns that loop into one
  # completion.
  #
  # Only the queued branch pays the extra call, and only the run's terminal
  # state can redirect it: a lookup that fails, or a run still live, leaves
  # the existing recovery untouched.
  #
  # A `queued` job that already names a runner has been assigned and its
  # status is lagging, so it is treated as `in_progress`.
  defp effective_gh_status(_installation, _orphan, %{status: "queued", runner_name: runner_name})
       when is_binary(runner_name) and runner_name != "" do
    {"in_progress", nil}
  end

  defp effective_gh_status(installation, orphan, %{status: "queued", conclusion: conclusion}) do
    case run_status(installation, orphan) do
      {:ok, %{status: "completed", conclusion: run_conclusion}} -> {"completed", run_conclusion || ""}
      _ -> {"queued", conclusion}
    end
  end

  defp effective_gh_status(_installation, _orphan, %{status: status, conclusion: conclusion}) do
    {status, conclusion}
  end

  # Rows enqueued before the run id was recorded carry the column's `0`
  # default, which addresses no run.
  defp run_status(installation, %{repository: repository, workflow_run_id: workflow_run_id})
       when is_binary(repository) and repository != "" and is_integer(workflow_run_id) and workflow_run_id > 0 do
    GitHubClient.workflow_run_status(installation, repository, workflow_run_id)
  end

  defp run_status(_installation, _orphan), do: {:error, :unaddressable}

  defp handle_gh_status(
         "queued",
         _conclusion,
         %{workflow_job_id: workflow_job_id, pod_name: pod_name} = orphan,
         account,
         evidence,
         stage
       ) do
    # GitHub still has this job queued, so the runner minted for it never
    # took it. That does NOT mean the Pod holding the claim is idle: GitHub
    # assigns jobs to any label-eligible runner, so it may be busy executing
    # a sibling's job. Releasing on the strength of the claimed job's status
    # alone would delete a live runner's row mid-job, and the executor's
    # `completed` webhook would then find nothing to free — under-counting a
    # working runner for the rest of its run.
    #
    # `executed_workflow_job_id` is set once GitHub proves this runner took
    # some job, so it's the busy signal: skip those and let the executor's
    # completion (or the Pod stopping) free the slot.
    #
    # That proof arrives on GitHub's `in_progress` webhook, and when GitHub
    # lags, its webhooks and its job API lag together, so the row reads
    # `queued` with nothing recorded against it for minutes while the runner
    # works. The Pod's own report does not depend on GitHub: a Pod whose
    # runner was started is occupied until it stops, and releasing its
    # claim stops counting it, so the account's concurrency limit admits
    # one VM more than it allows. On 2026-10-21 and 10-22 this release ran
    # up to 125 times an hour for the `tuist` account, which then held 6
    # macOS runners against a limit of 4. A runner GitHub never gives a job
    # exits at the pool's idle timeout, and the Pod's stop then reaches the
    # `:pod_stopped` path.
    #
    # Unless the Pod has already stopped, which is what `:pod_stopped`
    # carries. A gone Pod is not busy, so the guard's premise is false and
    # holding it would strand the job until the executed job's completion
    # or `PodReconciliationWorker`'s much longer confirmation. The release
    # below stays handle-guarded on `claimed_at`, so this cannot reach a
    # replacement Pod's claim.
    case busy_signal(evidence, workflow_job_id, pod_name) do
      nil ->
        case stage do
          :first_sighting -> schedule_queued_confirmation(orphan, account, evidence)
          :confirmation -> requeue_orphan(orphan, account)
        end

      signal ->
        Logger.info("runners: orphaned running row — claim's runner is busy; leaving it",
          workflow_job_id: workflow_job_id,
          account: account.name,
          pod: pod_name,
          signal: signal
        )

        false
    end
  end

  defp busy_signal(:aged_out, workflow_job_id, pod_name) do
    cond do
      Claims.executing?(workflow_job_id) -> "executing"
      runner_started?(pod_name) -> "pod"
      true -> nil
    end
  end

  defp busy_signal(_evidence, _workflow_job_id, _pod_name), do: nil

  # Whether the Pod reports that its runner was started. A macOS guest
  # writes the `claimed` heartbeat once dispatch handed it a runner
  # credential (tart-kubelet republishes it on the Pod); a Linux Pod's
  # dispatch poller is an init container that exits at that moment. A
  # Pod that is being deleted, that cannot be read, or that reports
  # neither, as one on a host without the heartbeat does, is not busy on
  # this evidence.
  defp runner_started?(pod_name) when is_binary(pod_name) and pod_name != "" do
    case K8sClient.get_pod(Environment.runners_namespace(), pod_name) do
      {:ok, %{"metadata" => metadata} = pod} ->
        is_nil(metadata["deletionTimestamp"]) and
          (get_in(metadata, ["annotations", @runner_heartbeat_state_annotation]) == @runner_heartbeat_claimed or
             poller_exited?(pod))

      _ ->
        false
    end
  end

  defp runner_started?(_pod_name), do: false

  defp poller_exited?(pod) do
    pod
    |> get_in(["status", "initContainerStatuses"])
    |> List.wrap()
    |> Enum.any?(&(&1["name"] == "poller" and is_map(get_in(&1, ["state", "terminated"]))))
  end

  defp handle_gh_status("in_progress", _conclusion, _orphan, _account, _evidence, _stage), do: false

  defp handle_gh_status(
         "completed",
         conclusion,
         %{workflow_job_id: workflow_job_id, pod_name: pod_name, fleet_name: fleet_name},
         account,
         _evidence,
         _stage
       ) do
    # GH has a terminal status but we never saw the corresponding
    # `workflow_job.completed` webhook (or it was retry-exhausted
    # before reaching us). Without releasing here, the PG claim
    # stays in `lifecycle_state='running'` forever — StaleClaimsWorker
    # excludes `running`, and this worker would see the same row
    # every minute. The GH lookup already proves the job is not
    # live, so free the cap slot ourselves.
    #
    # Claim-first matches the webhook path
    # (`Tuist.Runners.Dispatch.mark_completed`): frees the slot the
    # instant we know, then records the terminal lifecycle state.
    Logger.warning("runners: orphaned running row — GH completed, freeing claim",
      workflow_job_id: workflow_job_id,
      account: account.name,
      pod: pod_name,
      conclusion: conclusion || ""
    )

    safe_complete_pg(workflow_job_id)
    safe_complete_job(workflow_job_id, conclusion || "")

    :telemetry.execute(
      Telemetry.event_name_recovery(),
      %{count: 1},
      %{kind: "orphan_completed", fleet: fleet_name}
    )

    true
  end

  defp handle_gh_status(other, _conclusion, %{workflow_job_id: workflow_job_id}, _account, _evidence, _stage) do
    # Unknown / future GH status. Log and skip; if it's actually
    # terminal we'll catch it on a later tick once GitHub-side
    # state settles or the 404 fallback above handles retention.
    Logger.debug("runners: orphan worker skipping unrecognised GH state",
      workflow_job_id: workflow_job_id,
      status: other
    )

    false
  end

  # Unique per claim so the sweep, the pod-gone arm and targeted mode
  # seeing the same `queued` answer schedule one confirmation between
  # them. A failed insert leaves the row `running`, and the next sweep
  # schedules it again.
  defp schedule_queued_confirmation(
         %{workflow_job_id: workflow_job_id, claimed_at: claimed_at, pod_name: pod_name},
         account,
         evidence
       ) do
    Logger.info("runners: orphaned running row — GH reports queued; confirming before recovering",
      workflow_job_id: workflow_job_id,
      account: account.name,
      pod: pod_name
    )

    %{
      "workflow_job_id" => workflow_job_id,
      "confirm_claimed_at" => DateTime.to_iso8601(claimed_at),
      "evidence" => Atom.to_string(evidence)
    }
    |> new(
      schedule_in: @queued_confirm_after_seconds,
      unique: [
        period: @queued_confirm_after_seconds * 2,
        keys: [:workflow_job_id, :confirm_claimed_at],
        states: [:available, :scheduled, :executing]
      ]
    )
    |> Oban.insert()
    |> case do
      {:ok, _job} ->
        :ok

      {:error, reason} ->
        Logger.warning("runners: failed to schedule orphan confirmation; the sweep will retry",
          workflow_job_id: workflow_job_id,
          reason: inspect(reason)
        )
    end

    false
  end

  defp requeue_orphan(
         %{
           workflow_job_id: workflow_job_id,
           claimed_at: claimed_at,
           started_at: started_at,
           pod_name: pod_name,
           fleet_name: fleet_name
         },
         account
       ) do
    Logger.warning("runners: orphaned running row — GH still queued, recovering",
      workflow_job_id: workflow_job_id,
      account: account.name,
      pod: pod_name
    )

    # `Claims.release/2` deletes the claim and re-queues the lifecycle
    # row in one transaction. `:stale_claim` means the claim is already
    # gone — either the pod-stopped report released it ahead of this
    # targeted run, or another Pod re-claimed the job with a newer
    # handle. The lifecycle row tells the two apart: it still carries
    # our `claimed_at` only in the former case, so the handle-guarded
    # requeue finishes that release and is a no-op for the latter.
    released =
      case Claims.release(workflow_job_id, claimed_at) do
        :ok -> :ok
        {:error, :stale_claim} -> WorkflowJobs.requeue_by_handle(workflow_job_id, claimed_at)
      end

    case released do
      :ok ->
        :telemetry.execute(
          Telemetry.event_name_recovery(),
          %{count: 1, stranded_ms: stranded_ms(started_at)},
          %{kind: "orphan_requeued", fleet: fleet_name}
        )

        true

      :noop ->
        false
    end
  end

  defp stranded_ms(%DateTime{} = started_at) do
    DateTime.utc_now() |> DateTime.diff(started_at, :millisecond) |> max(0)
  end

  defp stranded_ms(_started_at), do: 0

  # `Claims.complete/1` is idempotent and deletes the PG row
  # regardless of the claim handle. Used here because the GH-side
  # job is already terminal — we don't care about handle races, we
  # just want the cap slot back.
  defp safe_complete_pg(workflow_job_id) do
    :ok = Claims.complete(workflow_job_id)
  rescue
    e ->
      Logger.warning("runners: Claims.complete failed in orphan worker; will retry next tick",
        workflow_job_id: workflow_job_id,
        release_error: Exception.message(e)
      )

      :error
  end

  # Terminal lifecycle transition. `Jobs.complete` returns
  # `{:error, :not_found}` when no lifecycle row exists — fine, the
  # claim is already freed by `safe_complete_pg/1`.
  defp safe_complete_job(workflow_job_id, conclusion) do
    case Jobs.complete(workflow_job_id, conclusion) do
      {:ok, _} -> :ok
      {:error, :not_found} -> :ok
    end
  rescue
    e ->
      Logger.warning("runners: Jobs.complete failed in orphan worker; will resolve on next webhook redelivery",
        workflow_job_id: workflow_job_id,
        release_error: Exception.message(e)
      )

      :error
  end
end
