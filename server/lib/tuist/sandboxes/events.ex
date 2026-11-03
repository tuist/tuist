defmodule Tuist.Sandboxes.Events do
  @moduledoc """
  Records sandbox lifecycle changes to `sandbox_events` for the dashboard's
  analytics. A sandbox runs from a `started` event until the next `paused`,
  `archived`, `failed` or `deleted` one.
  """

  alias Tuist.Sandboxes.Sandbox
  alias Tuist.Sandboxes.SandboxEvent

  @events ~w(created started paused archived failed deleted)
  @stop_events ~w(paused archived failed deleted)

  def stop_events, do: @stop_events

  def record(%Sandbox{} = sandbox, event) when event in @events do
    SandboxEvent.Buffer.insert(%{
      id: UUIDv7.generate(),
      account_id: sandbox.account_id,
      sandbox_id: sandbox.id,
      event: event,
      source: source(sandbox),
      vcpus: sandbox.vcpus,
      memory_mb: sandbox.memory_mb,
      inserted_at: NaiveDateTime.utc_now()
    })

    :ok
  end

  @doc """
  Records the event for a state change, if the change is one.
  """
  def record_transition(%Sandbox{state: state}, %Sandbox{state: state}), do: :ok

  # A restore that could not boot puts the sandbox back where it was.
  def record_transition(%Sandbox{state: :creating}, %Sandbox{state: :archived}), do: :ok

  def record_transition(%Sandbox{}, %Sandbox{} = sandbox) do
    case transition_event(sandbox.state) do
      nil -> :ok
      event -> record(sandbox, event)
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
