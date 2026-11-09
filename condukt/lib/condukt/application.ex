defmodule Condukt.Application do
  @moduledoc false

  use Application

  # The control channel for a `:decide` network policy is a per-session
  # `...K8s.ControlBridge` started as a `:transient` child of this
  # DynamicSupervisor (the standard "dynamic children under the app
  # root" pattern). Bounded restart intensity so a genuinely buggy
  # bridge can't hot-loop the whole pool; a bridge that merely can't
  # reach its control port gives up `:normal` and is dropped, not
  # restarted, so it never counts against the intensity.
  @control_channel_supervisor Condukt.Sandbox.NetworkPolicy.K8s.ControlChannelSupervisor

  def control_channel_supervisor, do: @control_channel_supervisor

  @impl true
  def start(_type, _args) do
    children =
      [Condukt.SessionStore.Memory.Table] ++
        Condukt.Sessions.child_specs() ++
        [
          {DynamicSupervisor,
           name: @control_channel_supervisor, strategy: :one_for_one, max_restarts: 10, max_seconds: 60}
        ]

    Supervisor.start_link(children, strategy: :one_for_one, name: Condukt.Supervisor)
  end
end
