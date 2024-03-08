defmodule TuistCloud.Application do
  # See https://hexdocs.pm/elixir/Application.html
  # for more information on OTP Applications
  @moduledoc false

  use Application

  @impl true
  def start(_type, _args) do
    load_secrets()

    children = [
      TuistCloudWeb.Telemetry,
      TuistCloud.Repo,
      {DNSCluster, query: Application.get_env(:tuist_cloud, :dns_cluster_query) || :ignore},
      {Phoenix.PubSub, name: TuistCloud.PubSub},
      # Start the Finch HTTP client for sending emails
      {Finch, name: TuistCloud.Finch},
      # Start a worker by calling: TuistCloud.Worker.start_link(arg)
      # {TuistCloud.Worker, arg},
      # Start to serve requests, typically the last entry
      TuistCloudWeb.Endpoint
    ]

    # See https://hexdocs.pm/elixir/Supervisor.html
    # for other strategies and supported options
    opts = [strategy: :one_for_one, name: TuistCloud.Supervisor]
    Supervisor.start_link(children, opts)
  end

  # Tell Phoenix to update the endpoint configuration
  # whenever the application is updated.
  @impl true
  def config_change(changed, _new, removed) do
    TuistCloudWeb.Endpoint.config_change(changed, removed)
    :ok
  end

  def load_secrets() do
    master_key_path = Path.join("priv/secrets", "master.key")
    master_key_env_variable = "PHX_MASTER_KEY"

    if System.get_env(master_key_env_variable) || File.exists?(master_key_path) do
      key = System.get_env(master_key_env_variable) || File.read!(master_key_path)
      Application.put_env(:tuist_cloud, :secrets, EncryptedSecrets.read!(key))
    else
      Application.put_env(:tuist_cloud, :secrets, %{})
    end
  end
end
