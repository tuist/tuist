defmodule Condukt.Test.OutageSandbox do
  @moduledoc false
  # A local sandbox whose process reads fail while `outage` exists in its
  # working directory, as while its node restarts.
  @behaviour Condukt.Sandbox

  alias Condukt.Sandbox.Local

  @impl true
  def init(opts), do: Local.init(opts)
  @impl true
  defdelegate shutdown(local), to: Local
  @impl true
  defdelegate cwd(local), to: Local
  @impl true
  defdelegate read_file(local, path), to: Local
  @impl true
  defdelegate write_file(local, path, content), to: Local
  @impl true
  defdelegate edit_file(local, path, old_text, new_text), to: Local
  @impl true
  defdelegate exec(local, command, opts), to: Local
  @impl true
  defdelegate start_process(local, id, command, opts), to: Local
  @impl true
  defdelegate stop_process(local, id), to: Local
  @impl true
  defdelegate write_process(local, id, data, opts), to: Local

  @impl true
  def read_process(local, id, offset, opts) do
    if File.exists?(Path.join(local.cwd, "outage")),
      do: {:error, :unavailable},
      else: Local.read_process(local, id, offset, opts)
  end
end
