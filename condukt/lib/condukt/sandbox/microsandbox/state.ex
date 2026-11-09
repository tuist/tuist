defmodule Condukt.Sandbox.Microsandbox.State do
  @moduledoc false

  defstruct [:session, :base_cwd, :shell, :nif_module, mounts: []]
end
