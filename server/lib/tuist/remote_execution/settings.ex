defmodule Tuist.RemoteExecution.Settings do
  @moduledoc """
  What an account executes with, resolved by `Tuist.RemoteExecution.available_settings/1`:
  its vCPU and memory limits from the account row, and the image, CAS and
  executor endpoint of the deployment. `max_concurrency` is how many VMs of
  the default shape the limits hold.

  An action asks for a larger VM with the `tuist-memory-gb` execution
  property, which the gateway passes on as `memory_gb`. Each size has two
  vCPUs per 4 GB; the workers offer the same shapes
  (`infra/helm/remote-execution`). Every size gets a workspace disk of
  `vm_workspace_gb/0`, which the workers' template snapshots are built with
  (`TEMPLATE_WORKSPACE_GB` in the same chart).
  """
  @vm_vcpus 2
  @vm_memory_mb 4096
  @vm_workspace_gb 30
  @memory_sizes_gb [4, 8, 16, 32]

  defstruct [:vcpus, :memory_gb, :max_concurrency, :image_tag, :cas_endpoint, :executor_endpoint]

  def vm_vcpus, do: @vm_vcpus
  def vm_memory_mb, do: @vm_memory_mb
  def vm_workspace_gb, do: @vm_workspace_gb
  def default_memory_gb, do: div(@vm_memory_mb, 1024)
  def memory_sizes_gb, do: @memory_sizes_gb

  def shape(memory_gb) when memory_gb in @memory_sizes_gb,
    do: %{vcpus: div(memory_gb * @vm_vcpus * 1024, @vm_memory_mb), memory_mb: memory_gb * 1024}

  @doc "Whether the account's limits hold one VM of the size at all."
  def fits?(%__MODULE__{} = settings, memory_gb) do
    %{vcpus: vcpus, memory_mb: memory_mb} = shape(memory_gb)
    vcpus <= settings.vcpus and memory_mb <= settings.memory_gb * 1024
  end

  def max_concurrency(vcpus, memory_gb), do: min(div(vcpus, @vm_vcpus), div(memory_gb * 1024, @vm_memory_mb))
end
