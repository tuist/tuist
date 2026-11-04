# Synthetic sandbox data for local UI previews, never production measurements.
# Run after the standard seeds with: mix run priv/repo/seed_sandboxes.exs
#
# Gives the `tuist` organization 60 days of `sandbox_events` history that never
# exceeds the account's limits, the `sandboxes` rows still alive now (running,
# paused, archived and failed), two project snapshots and a connected Amp
# integration. Reruns replace the account's sandbox data.
import Ecto.Query

alias Tuist.Accounts
alias Tuist.IngestRepo
alias Tuist.Repo
alias Tuist.Sandboxes.AmpIntegration
alias Tuist.Sandboxes.DiskSnapshot
alias Tuist.Sandboxes.Sandbox
alias Tuist.Sandboxes.SandboxEvent

if Mix.env() != :dev, do: raise("Sandbox seeds are only supported in development")

organization = Accounts.get_organization_by_handle("tuist") || raise "Run priv/repo/seeds.exs first"
account_id = organization.account.id
now = DateTime.truncate(DateTime.utc_now(), :second)
history_start = now |> DateTime.add(-60, :day) |> Map.merge(%{hour: 0, minute: 0, second: 0})
:rand.seed(:exsss, {2026, 11, 3})

Repo.delete_all(from(s in DiskSnapshot, where: s.account_id == ^account_id))
Repo.delete_all(from(s in Sandbox, where: s.account_id == ^account_id))
Repo.delete_all(from(i in AmpIntegration, where: i.account_id == ^account_id))

IngestRepo.query!("ALTER TABLE sandbox_events DELETE WHERE account_id = #{account_id} SETTINGS mutations_sync = 2")

integration =
  %AmpIntegration{account_id: account_id, revision: 0}
  |> AmpIntegration.changeset("aop_live_seeded_preview_token")
  |> Ecto.Changeset.put_change(:status, :running)
  |> Ecto.Changeset.put_change(:last_checked_at, now)
  |> Repo.insert!()

templates = ["tuist-server", "tuist-cli", "noora", "handbook"]

# Five lanes, one per sandbox the account can run at once. The first three
# lanes take any shape and the last two at most 4 vCPUs, so even a full
# account stays within its 32 vCPUs and 64 GB.
lanes = [
  %{busy: 0.9, shapes: [{2, 4096}, {4, 8192}, {8, 16_384}]},
  %{busy: 0.75, shapes: [{2, 4096}, {4, 8192}, {8, 16_384}]},
  %{busy: 0.5, shapes: [{2, 4096}, {4, 8192}, {8, 16_384}]},
  %{busy: 0.3, shapes: [{2, 4096}, {4, 8192}]},
  %{busy: 0.18, shapes: [{2, 4096}, {4, 8192}]}
]

history_seconds = DateTime.diff(now, history_start)

# How likely a lane starts a session in a 15-minute step: working hours on
# weekdays, quieter evenings and weekends, growing over the 60 days.
start_probability = fn at, busy ->
  weekday? = Date.day_of_week(at) <= 5

  hours =
    cond do
      not weekday? -> 0.12
      at.hour in 7..17 -> 1.0
      at.hour in 18..21 -> 0.35
      true -> 0.06
    end

  growth = 0.55 + 0.55 * DateTime.diff(at, history_start) / history_seconds
  min(hours * busy * growth * 0.45, 0.95)
end

session_minutes = fn -> min(12 + round(-:math.log(:rand.uniform()) * 75), 360) end

new_sandbox = fn lane, at ->
  {vcpus, memory_mb} = Enum.random(lane.shapes)
  orb = 6 |> :crypto.strong_rand_bytes() |> Base.encode16(case: :lower)

  %{
    id: Ecto.UUID.generate(),
    orb: orb,
    template: Enum.random(templates),
    vcpus: vcpus,
    memory_mb: memory_mb,
    created_at: at,
    events: [{"created", at}],
    boots: %{},
    setup: nil,
    last_active_at: at
  }
end

# A new sandbox's first boot: cold from the template followed by
# `.agents/setup`, or from a project snapshot, which Orbs use more and more
# over the 60 days. Answers the sandbox, when it booted and when it was ready.
boot = fn sandbox, at ->
  progress = DateTime.diff(at, history_start) / history_seconds

  if :rand.uniform() < 0.6 - 0.35 * progress do
    boot_ms = 15_000 + :rand.uniform(30_000)
    booted_at = DateTime.add(at, boot_ms, :millisecond)
    setup_s = (240 * :math.exp(:rand.normal() * 0.45)) |> round() |> max(60) |> min(1200)
    setup_end = DateTime.add(booted_at, 20 + :rand.uniform(20) + setup_s, :second)

    {%{
       sandbox
       | boots: %{booted_at => %{boot_source: "template", duration_ms: boot_ms}},
         setup: {setup_end, setup_s * 1000}
     }, booted_at, setup_end}
  else
    boot_ms = 3_000 + :rand.uniform(6_000)
    booted_at = DateTime.add(at, boot_ms, :millisecond)
    {%{sandbox | boots: %{booted_at => %{boot_source: "disk_snapshot", duration_ms: boot_ms}}}, booted_at, booted_at}
  end
end

# Ends a sandbox's life after its last session: archived a day after the
# pause, deleted a few days later. A third are restored from the archive
# once for a short session first. Steps still in the future are left out,
# so the sandbox is paused or archived now.
retire = fn sandbox, paused_at ->
  archived_at = DateTime.add(paused_at, 24 * 60 + :rand.uniform(120), :minute)

  {restore, boots, last_archived_at} =
    if :rand.uniform() < 0.35 do
      restore_ms = 20_000 + :rand.uniform(40_000)
      started_at = DateTime.add(archived_at, :rand.uniform(48 * 60) * 60 + div(restore_ms, 1000), :second)
      repaused_at = DateTime.add(started_at, 20 + :rand.uniform(70), :minute)
      rearchived_at = DateTime.add(repaused_at, 24 * 60 + :rand.uniform(120), :minute)

      {[{"started", started_at}, {"paused", repaused_at}, {"archived", rearchived_at}],
       Map.put(sandbox.boots, started_at, %{boot_source: "archive", duration_ms: restore_ms}), rearchived_at}
    else
      {[], sandbox.boots, archived_at}
    end

  deleted_at = DateTime.add(last_archived_at, 1 + :rand.uniform(5), :day)

  ([{"archived", archived_at} | restore] ++ [{"deleted", deleted_at}])
  |> Enum.filter(fn {_event, at} -> DateTime.before?(at, now) end)
  |> Enum.reduce(%{sandbox | boots: boots}, fn event, acc -> %{acc | events: [event | acc.events]} end)
end

fail = fn sandbox, failed_at ->
  deleted_at = DateTime.add(failed_at, 2 + :rand.uniform(4), :day)
  events = [{"failed", failed_at} | sandbox.events]
  events = if DateTime.before?(deleted_at, now), do: [{"deleted", deleted_at} | events], else: events
  %{sandbox | events: events}
end

simulate_lane = fn {lane, index} ->
  # The two busiest lanes are running now, so the page shows live usage.
  stop_at = if index < 2, do: DateTime.add(now, -(2 + index), :hour), else: now

  {done, current, _at} =
    history_start
    |> Stream.unfold(fn at -> {at, DateTime.add(at, 15, :minute)} end)
    |> Enum.reduce_while({[], nil, history_start}, fn step, {done, current, free_at} ->
      cond do
        not DateTime.before?(step, stop_at) ->
          {:halt, {done, current, free_at}}

        DateTime.before?(step, free_at) or :rand.uniform() > start_probability.(step, lane.busy) ->
          {:cont, {done, current, free_at}}

        true ->
          at = DateTime.add(step, :rand.uniform(14 * 60), :second)

          # Resume the lane's paused sandbox, unless it has been idle for a day.
          {done, sandbox} =
            if current && :rand.uniform() < 0.55 && DateTime.diff(at, current.last_active_at, :hour) < 24 do
              {done, current}
            else
              done = if current, do: [retire.(current, current.last_active_at) | done], else: done
              {done, new_sandbox.(lane, at)}
            end

          # A create that never boots.
          if sandbox.events == [{"created", sandbox.created_at}] and :rand.uniform() < 0.04 do
            failed = fail.(sandbox, DateTime.add(at, 40 + :rand.uniform(80), :second))
            {:cont, {[failed | done], nil, DateTime.add(at, 5, :minute)}}
          else
            {sandbox, started_at, ready_at} =
              if sandbox.events == [{"created", sandbox.created_at}], do: boot.(sandbox, at), else: {sandbox, at, at}

            ended_at = DateTime.add(started_at, session_minutes.() * 60 + :rand.uniform(59), :second)
            ended_at = if index < 2, do: Enum.min([ended_at, stop_at], DateTime), else: ended_at
            ended_at = [ended_at, DateTime.add(ready_at, 2, :minute)] |> Enum.max(DateTime) |> DateTime.truncate(:second)
            sandbox = %{sandbox | events: [{"started", started_at} | sandbox.events]}

            cond do
              not DateTime.before?(ended_at, now) ->
                {:cont, {done, %{sandbox | last_active_at: now}, ended_at}}

              :rand.uniform() < 0.035 ->
                {:cont, {[fail.(sandbox, ended_at) | done], nil, DateTime.add(ended_at, 10, :minute)}}

              true ->
                sandbox = %{sandbox | events: [{"paused", ended_at} | sandbox.events], last_active_at: ended_at}
                {:cont, {done, sandbox, DateTime.add(ended_at, 5 + :rand.uniform(55), :minute)}}
            end
          end
      end
    end)

  done =
    case current do
      nil -> done
      %{events: [{"started", _at} | _]} -> [current | done]
      paused -> [retire.(paused, paused.last_active_at) | done]
    end

  if index < 2 do
    # An open session that started a little while ago.
    created_at = DateTime.add(now, -(25 + index * 50), :minute)
    {sandbox, started_at, _ready_at} = lane |> new_sandbox.(created_at) |> boot.(created_at)
    [%{sandbox | events: [{"started", started_at} | sandbox.events], last_active_at: now} | done]
  else
    done
  end
end

sandboxes = lanes |> Enum.with_index() |> Enum.flat_map(simulate_lane)

# A boot's `started` event carries how it booted. Setup is recorded at the
# Orb's first pause, so an Orb that hasn't stopped yet has no setup event.
seeded_events = fn sandbox ->
  stopped? = Enum.any?(sandbox.events, fn {event, _at} -> event in ~w(paused archived failed deleted) end)

  setup =
    case sandbox.setup do
      {finished_at, duration_ms} when stopped? -> [{"setup", finished_at, %{duration_ms: duration_ms}}]
      _ -> []
    end

  boot_event =
    sandbox.events
    |> Enum.reverse()
    |> Enum.map(fn {event, at} ->
      if event == "started", do: {event, at, Map.get(sandbox.boots, at, %{})}, else: {event, at, %{}}
    end)

  boot_event ++ setup
end

events =
  for sandbox <- sandboxes, {event, at, extra} <- seeded_events.(sandbox) do
    %{
      id: UUIDv7.generate(),
      account_id: account_id,
      sandbox_id: sandbox.id,
      event: event,
      source: "amp",
      vcpus: sandbox.vcpus,
      memory_mb: sandbox.memory_mb,
      boot_source: Map.get(extra, :boot_source, ""),
      duration_ms: Map.get(extra, :duration_ms, 0),
      inserted_at: %{DateTime.to_naive(at) | microsecond: {elem(at.microsecond, 0), 6}}
    }
  end

events
|> Enum.chunk_every(5_000)
|> Enum.each(&IngestRepo.insert_all(SandboxEvent, &1, timeout: 120_000))

# The rows of sandboxes that aren't deleted, in the state their last event left them.
rows =
  for sandbox <- sandboxes, {last_event, last_at} = hd(sandbox.events), last_event != "deleted" do
    state =
      case last_event do
        "started" -> :running
        "paused" -> :paused
        "archived" -> :archived
        "failed" -> :error
      end

    paused_at = Enum.find_value(sandbox.events, fn {event, at} -> if event == "paused", do: at end)

    %{
      id: sandbox.id,
      account_id: account_id,
      amp_orb_id: "orb_" <> sandbox.orb,
      amp_integration_id: integration.id,
      template: sandbox.template,
      template_tag: "2026.10.30",
      vcpus: sandbox.vcpus,
      memory_mb: sandbox.memory_mb,
      workspace_gb: 50,
      state: state,
      node_name: if(state == :archived, do: nil, else: "sandbox-fsn1-#{rem(:erlang.phash2(sandbox.id), 3) + 1}"),
      hostname: "orb-#{sandbox.orb}",
      residency_work_id: nil,
      last_active_at: if(state == :running, do: now, else: sandbox.last_active_at),
      paused_at: if(state in [:paused, :archived], do: paused_at),
      archived_at: if(state == :archived, do: last_at),
      archive_bytes: if(state == :archived, do: (3 + :rand.uniform(9)) * 1_000_000_000),
      archive_store: if(state == :archived, do: "s3"),
      archive_key: if(state == :archived, do: "sandboxes/#{account_id}/#{sandbox.id}.tar.zst"),
      error_message:
        if(state == :error,
          do: "The sandbox node reported that the VM exited unexpectedly (exit status 137)."
        ),
      inserted_at: sandbox.created_at,
      updated_at: DateTime.truncate(last_at, :second)
    }
  end

# One running sandbox has an agent working in it right now.
rows =
  case Enum.find_index(rows, &(&1.state == :running)) do
    nil -> rows
    index -> List.update_at(rows, index, &%{&1 | residency_work_id: "work_seeded_preview"})
  end

Repo.insert_all(Sandbox, rows)

snapshot_sources = rows |> Enum.filter(&(&1.state in [:paused, :running])) |> Enum.take(2)

for {source, index} <- Enum.with_index(snapshot_sources) do
  Repo.insert!(%DiskSnapshot{
    account_id: account_id,
    amp_snapshot_id: "snap_#{source.template}_#{index + 1}",
    source_sandbox_id: source.id,
    node_name: source.node_name,
    template: source.template,
    template_tag: source.template_tag,
    workspace_gb: source.workspace_gb,
    state: :ready,
    last_used_at: DateTime.add(now, -(3 + index * 20), :hour)
  })
end

counts = Enum.frequencies_by(rows, & &1.state)

IO.puts("""
Seeded #{length(sandboxes)} sandboxes (#{length(events)} events over 60 days) for the tuist account.
Now: #{inspect(counts)}
Open http://localhost:#{System.get_env("TUIST_SERVER_PORT", "8080")}/tuist/sandboxes and log in as tuistrocks@tuist.dev / tuistrocks.
""")
