defmodule TuistRegistryWeb.UpController do
  use TuistRegistryWeb, :controller

  # The pod is a stateless read frontend (no DB, no Oban journal), so
  # `/up` just confirms the BEAM is alive and the Phoenix endpoint is
  # answering. Any deeper readiness (S3 reachability, registry bucket
  # presence) belongs on `/swift/availability` since SwiftPM probes that
  # before each registry operation.
  def index(conn, _params) do
    send_resp(conn, :ok, "UP! Version: " <> version())
  end

  defp version do
    System.get_env("KAMAL_VERSION") || System.get_env("RELEASE_VSN") || "unknown"
  end
end
