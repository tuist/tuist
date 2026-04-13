defmodule Tuist.Runners.OrchardConfig do
  @moduledoc false
  alias Tuist.Environment
  alias Tuist.Runners.RunnerConfiguration

  defstruct [:controller_url, :service_account_name, :service_account_token]

  def for_configuration(%RunnerConfiguration{provisioning_mode: :managed}) do
    {:ok,
     %__MODULE__{
       controller_url: Environment.get([:orchard, :controller_url]),
       service_account_name: Environment.get([:orchard, :service_account_name]),
       service_account_token: Environment.get([:orchard, :service_account_token])
     }}
  end

  def for_configuration(%RunnerConfiguration{provisioning_mode: :self_hosted} = config) do
    {:ok,
     %__MODULE__{
       controller_url: config.orchard_controller_url,
       service_account_name: config.orchard_service_account_name,
       service_account_token: config.orchard_encrypted_service_account_token
     }}
  end
end
