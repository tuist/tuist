defmodule Tuist.RemoteExecution.Settings do
  @moduledoc """
  What an account executes with, resolved by `Tuist.RemoteExecution.available_settings/1`:
  its vCPU and memory limits from the account row, and the image, CAS and
  executor endpoint of the deployment. `max_concurrency` is how many VMs of
  the default shape the limits hold.

  An action asks for another VM size with the `tuist-memory-gb` execution
  property, which the gateway passes on as `memory_gb`; with automatic task
  sizing (`Tuist.RemoteExecution.TaskSizes`) that is a floor and every VM
  boots with `burst_vcpus/0`. An action without the property runs in
  `default_memory_gb/1`, which is also the size of the warm pool and of
  leases: 4 GB, or 2 GB when the account's VMs burst, since their vCPUs no
  longer follow their memory and task sizing raises an action to what it
  measured. Each size has one vCPU per 2 GB, its guarantee
  when it bursts; the workers offer the same shapes
  (`infra/helm/remote-execution`). Every size gets a workspace disk of
  `vm_workspace_gb/0`, which the workers' template snapshots are built with
  (`TEMPLATE_WORKSPACE_GB` in the same chart).
  """
  @vm_vcpus 2
  @vm_memory_mb 4096
  @vm_workspace_gb 30
  @memory_sizes_gb [2, 4, 8, 16]
  # An account with automatic task sizing (`Tuist.RemoteExecution.TaskSizes`)
  # boots every VM with this many vCPUs, whatever its memory. The VM bursts
  # into idle cores; its cgroup weight is its guarantee, which the account's
  # vCPU limit counts: the shape's vCPUs until the action has been measured.
  @burst_vcpus 8
  @burst_default_memory_gb 2

  defstruct [
    :vcpus,
    :memory_gb,
    :max_concurrency,
    :image_tag,
    :cas_endpoint,
    :client_cas_endpoint,
    :executor_endpoint,
    burst: false
  ]

  def vm_vcpus, do: @vm_vcpus
  def vm_memory_mb, do: @vm_memory_mb
  def vm_workspace_gb, do: @vm_workspace_gb
  def default_memory_gb, do: div(@vm_memory_mb, 1024)

  @doc "The size of an action that asks for none, and of the account's warm and leased VMs."
  def default_memory_gb(%__MODULE__{burst: true}), do: @burst_default_memory_gb
  def default_memory_gb(_settings), do: default_memory_gb()
  def memory_sizes_gb, do: @memory_sizes_gb

  def shape(memory_gb) when memory_gb in @memory_sizes_gb,
    do: %{vcpus: div(memory_gb * @vm_vcpus * 1024, @vm_memory_mb), memory_mb: memory_gb * 1024}

  @doc "The vCPUs a VM of the size boots with: the shape's, or `@burst_vcpus` when the account bursts."
  def boot_vcpus(%__MODULE__{burst: true}, _memory_gb), do: @burst_vcpus
  def boot_vcpus(%__MODULE__{}, memory_gb), do: shape(memory_gb).vcpus

  def burst_vcpus, do: @burst_vcpus

  @doc "Whether the account's limits hold one VM of the size at all."
  def fits?(%__MODULE__{} = settings, memory_gb) do
    %{vcpus: vcpus, memory_mb: memory_mb} = shape(memory_gb)
    vcpus <= settings.vcpus and memory_mb <= settings.memory_gb * 1024
  end

  def max_concurrency(vcpus, memory_gb), do: min(div(vcpus, @vm_vcpus), div(memory_gb * 1024, @vm_memory_mb))
end
