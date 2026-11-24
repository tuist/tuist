defmodule Symptoms.PagingTest do
  use ExUnit.Case, async: false

  alias Symptoms.Paging

  @document %{"symptom_id" => "0190f6c0-0000-7000-8000-000000000001", "title" => "t", "revision" => 1}

  setup do
    previous = Application.get_env(:symptoms, :paging)
    on_exit(fn -> Application.put_env(:symptoms, :paging, previous) end)
  end

  test "is off by default: a page is only logged" do
    Application.put_env(:symptoms, :paging, enabled: false, webhook_url: "http://irm.invalid/hook")
    assert Paging.page(@document, DateTime.utc_now()) == :logged
  end

  test "posts to the IRM webhook when enabled" do
    test = self()

    plug = fn conn ->
      {:ok, body, conn} = Plug.Conn.read_body(conn)
      send(test, {:posted, Plug.Conn.get_req_header(conn, "authorization"), Jason.decode!(body)})
      Plug.Conn.send_resp(conn, 200, "ok")
    end

    Application.put_env(:symptoms, :paging,
      enabled: true,
      webhook_url: "http://irm.invalid/hook",
      token: "irm",
      req_options: [plug: plug]
    )

    assert Paging.page(@document, DateTime.utc_now()) == :sent
    assert_received {:posted, ["Bearer irm"], %{"alert_uid" => "0190f6c0-0000-7000-8000-000000000001"}}
  end
end
