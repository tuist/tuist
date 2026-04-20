defmodule Tuist.Runners.OrchardWorkerProvisioner.Stub do
  @moduledoc """
  No-op stub that matches the `Tuist.Runners.OrchardWorkerProvisioner.provision/1`
  signature for local end-to-end runs. Logs the request and returns `:ok`
  without attempting any SSH.
  """

  require Logger

  def provision(%{ip: ip, ssh_user: ssh_user} = _attrs) do
    Logger.info("[Provisioner stub] Would provision Orchard worker at #{ssh_user}@#{ip}")
    :ok
  end
end
