defmodule Tuist.Registry.Temporary do
  @moduledoc false

  def with_directory(fun) do
    path = Path.join(System.tmp_dir!(), "tuist-registry-#{Ecto.UUID.generate()}")
    File.mkdir!(path)
    File.chmod!(path, 0o700)
    owner = self()
    # A large killed clone must not block a shared temp-file server and every
    # other release job. Each owner has an independent cleanup monitor.
    cleaner =
      spawn(fn ->
        ref = Process.monitor(owner)

        receive do
          {:DOWN, ^ref, :process, _, _} -> :ok
          :cleaned -> Process.demonitor(ref, [:flush])
        end

        # MuonTrap permits 500ms for the dying process group. Cleanup must also
        # cover entries recreated after the caller's first deletion attempt.
        Process.sleep(750)
        File.rm_rf(path)
        Process.sleep(750)
        File.rm_rf(path)
      end)

    try do
      fun.(path)
    after
      File.rm_rf(path)
      send(cleaner, :cleaned)
    end
  end
end
