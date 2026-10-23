Code.require_file("boot.exs", __DIR__)
port = "TUIST_E2E_PORT" |> System.fetch_env!() |> String.to_integer()
directory = System.get_env("TUIST_E2E_OUTPUT_DIR", "/tmp/tuist-scale-e2e")
File.mkdir_p!(directory)
File.write!(Path.join(directory, "server-#{port}.pid"), System.pid())

:ok =
  (
    ScaleEndToEnd.boot(port)
    :ok
  )

Process.sleep(:infinity)
