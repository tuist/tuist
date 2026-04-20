defmodule Tuist.Scaleway do
  @moduledoc """
  Context module for Scaleway Apple Silicon server management.

  Used by the managed Tuist Runners fleet to provision and release
  Scaleway bare-metal Macs that host Orchard workers.
  """

  alias Tuist.Environment

  defstruct [:secret_key, :project_id]

  def config do
    if stub?() do
      {:ok, %__MODULE__{secret_key: "stub", project_id: "stub"}}
    else
      with {:ok, secret_key} <- fetch_env([:scaleway, :secret_key]),
           {:ok, project_id} <- fetch_env([:scaleway, :project_id]) do
        {:ok, %__MODULE__{secret_key: secret_key, project_id: project_id}}
      end
    end
  end

  defp stub? do
    Application.get_env(:tuist, :scaleway_client) == Tuist.Scaleway.Stub
  end

  defp fetch_env(key) do
    case Environment.get(key) do
      nil -> {:error, {:missing_config, key}}
      "" -> {:error, {:missing_config, key}}
      value -> {:ok, value}
    end
  end
end
