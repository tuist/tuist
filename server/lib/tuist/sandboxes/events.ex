defmodule Tuist.Sandboxes.Events do
  @moduledoc """
  Records sandbox lifecycle changes to `sandbox_events` for the dashboard's
  analytics. A sandbox runs from a `started` event until the next `paused`,
  `archived`, `failed` or `deleted` one.
  """

  alias Tuist.Sandboxes.Sandbox
  alias Tuist.Sandboxes.SandboxEvent

  @events ~w(created started paused archived failed deleted setup)
  @stop_events ~w(paused archived failed deleted)
  @boot_sources ~w(template disk_snapshot archive)

  def stop_events, do: @stop_events

  @doc """
  Records `event` for the sandbox now. `:boot_source` and `:duration_ms`
  describe a boot on its `started` event, and `:inserted_at` dates an event
  that happened before it was observed.
  """
  def record(%Sandbox{} = sandbox, event, extra \\ %{}) when event in @events do
    SandboxEvent.Buffer.insert(%{
      id: UUIDv7.generate(),
      account_id: sandbox.account_id,
      sandbox_id: sandbox.id,
      event: event,
      source: source(sandbox),
      vcpus: sandbox.vcpus,
      memory_mb: sandbox.memory_mb,
      workspace_gb: sandbox.workspace_gb || 0,
      boot_source: Map.get(extra, :boot_source, ""),
      duration_ms: Map.get(extra, :duration_ms, 0),
      inserted_at: Map.get_lazy(extra, :inserted_at, &NaiveDateTime.utc_now/0)
    })

    :ok
  end

  @doc """
  The extra attributes of a boot's `started` event: what it booted from
  (a template, a disk snapshot or an archive) and the `duration_ms` it
  took to place and boot the VM.
  """
  def boot(source, duration_ms) when source in @boot_sources and is_integer(duration_ms),
    do: %{boot_source: source, duration_ms: max(duration_ms, 0)}

  @doc """
  Records an Orb's `.agents/setup` run from its log's birth and modification
  times (Unix seconds), dated when setup finished. A log older than the
  sandbox came with the disk snapshot it was cloned from, so setup did not
  run in this sandbox.
  """
  def record_setup(%Sandbox{} = sandbox, started_s, finished_s) when is_integer(started_s) and is_integer(finished_s) do
    started_at = DateTime.from_unix!(started_s)
    finished_at = DateTime.from_unix!(finished_s)

    if started_s > 0 and not DateTime.before?(started_at, sandbox.inserted_at) and
         not DateTime.before?(finished_at, started_at) do
      record(sandbox, "setup", %{
        duration_ms: (finished_s - started_s) * 1000,
        inserted_at: %{DateTime.to_naive(finished_at) | microsecond: {0, 6}}
      })
    else
      :ok
    end
  end

  @doc """
  Records the event for a state change, if the change is one.
  """
  def record_transition(previous, sandbox, extra \\ %{})

  def record_transition(%Sandbox{state: state}, %Sandbox{state: state}, _extra), do: :ok

  # A restore that could not boot puts the sandbox back where it was.
  def record_transition(%Sandbox{state: :creating}, %Sandbox{state: :archived}, _extra), do: :ok

  def record_transition(%Sandbox{}, %Sandbox{} = sandbox, extra) do
    case transition_event(sandbox.state) do
      nil -> :ok
      event -> record(sandbox, event, extra)
    end
  end

  defp transition_event(:running), do: "started"
  defp transition_event(:paused), do: "paused"
  defp transition_event(:archived), do: "archived"
  defp transition_event(:error), do: "failed"
  defp transition_event(_state), do: nil

  def source(%Sandbox{amp_orb_id: orb_id}) when is_binary(orb_id), do: "amp"
  def source(%Sandbox{agent_environment_id: id}) when not is_nil(id), do: "claude"
  def source(%Sandbox{}), do: "api"
end
