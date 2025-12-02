defmodule Tuist.Runners.SSHKeyCallback do
  @moduledoc """
  Custom SSH key callback module for Erlang's SSH client.
  
  This module provides the private key to the SSH client by reading from a
  temporary file. It implements the :ssh_client_key_api behavior.
  
  Since OpenSSH format keys require special handling, we write the key to
  a temporary file and let Erlang's SSH library read it using standard methods.
  """

  @behaviour :ssh_client_key_api

  @doc """
  Called by SSH client to check if a host key is trusted.
  We accept all hosts since we use silently_accept_hosts: true.
  """
  @impl :ssh_client_key_api
  def is_host_key(key, host, port, algorithm, opts) do
    # Delegate to the default implementation which respects silently_accept_hosts
    :ssh_file.is_host_key(key, host, port, algorithm, opts)
  end

  @doc """
  Called by SSH client to get the user's private key.
  Reads the key from the temporary file path passed in options.
  """
  @impl :ssh_client_key_api
  def user_key(algorithm, opts) do
    # Get the key file path from options
    key_file = Keyword.get(opts, :key_file)

    if key_file do
      # Use ssh_file to read the key from the file
      :ssh_file.user_key(algorithm, opts)
    else
      {:error, :no_key}
    end
  end

  @doc """
  Called by SSH client to add a new host key.
  We don't persist host keys, so this is a no-op.
  """
  @impl :ssh_client_key_api
  def add_host_key(_host, _port, _key, _opts) do
    :ok
  end
end
