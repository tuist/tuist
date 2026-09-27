Code.require_file("boot.exs", __DIR__)
port = "TUIST_E2E_PORT" |> System.fetch_env!() |> String.to_integer()
File.write!("/tmp/tuist-scale-e2e/server-#{port}.pid", System.pid())

:ok =
  (
    ScaleEndToEnd.boot(port)
    :ok
  )

Process.sleep(:infinity)
