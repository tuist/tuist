defmodule Condukt.Sandbox.Kubernetes.State do
  @moduledoc false

  defstruct [
    :conn,
    :namespace,
    :pod_name,
    :container,
    :base_cwd,
    :id,
    :delete_on_shutdown,
    :heartbeat_pid,
    :net_policy,
    :net_resource_names,
    :net_channel_pid,
    :owner_pid
  ]
end
