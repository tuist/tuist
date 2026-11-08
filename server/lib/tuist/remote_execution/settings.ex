defmodule Tuist.RemoteExecution.Settings do
  @moduledoc """
  What an account executes with, resolved by `Tuist.RemoteExecution.available_settings/1`:
  its vCPU and memory limits from the account row, and the image, CAS and
  executor endpoint of the deployment. `max_concurrency` is how many VMs of
  the fixed shape the limits hold.
  """
  @vm_vcpus 2
  @vm_memory_mb 4096

  defstruct [:vcpus, :memory_gb, :max_concurrency, :image_tag, :cas_endpoint, :executor_endpoint]

  def vm_vcpus, do: @vm_vcpus
  def vm_memory_mb, do: @vm_memory_mb

  def max_concurrency(vcpus, memory_gb), do: min(div(vcpus, @vm_vcpus), div(memory_gb * 1024, @vm_memory_mb))
end
