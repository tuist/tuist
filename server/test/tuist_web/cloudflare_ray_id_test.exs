defmodule TuistWeb.CloudflareRayIdTest do
  use ExUnit.Case, async: true

  import Plug.Conn
  import Plug.Test

  alias TuistWeb.RemoteIp

  test "accepts Ray IDs only from a Cloudflare edge or the private ingress behind it" do
    conn = :post |> conn("/-/faro/collect") |> put_req_header("cf-ray", "a3e837c27a56c4cf-SEA")
    assert RemoteIp.cloudflare_ray_id(%{conn | remote_ip: {104, 22, 160, 71}}) == "a3e837c27a56c4cf-SEA"

    ingress = %{conn | remote_ip: {10, 0, 0, 1}}

    assert ingress |> put_req_header("x-tuist-edge-address", "104.22.160.71") |> RemoteIp.cloudflare_ray_id() ==
             "a3e837c27a56c4cf-SEA"

    refute RemoteIp.cloudflare_ray_id(ingress)
    refute RemoteIp.cloudflare_ray_id(%{conn | remote_ip: {203, 0, 113, 1}})
    refute ingress |> put_req_header("x-tuist-edge-address", "203.0.113.1") |> RemoteIp.cloudflare_ray_id()

    refute conn
           |> Map.put(:remote_ip, {104, 22, 160, 71})
           |> put_req_header("cf-ray", "arbitrary")
           |> RemoteIp.cloudflare_ray_id()
  end
end
