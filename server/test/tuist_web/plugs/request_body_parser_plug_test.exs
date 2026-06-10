defmodule TuistWeb.Plugs.RequestBodyParserPlugTest do
  use ExUnit.Case, async: true

  import Plug.Conn
  import Plug.Test

  alias TuistWeb.Plugs.RequestBodyParserPlug

  defmodule TimeoutBodyReader do
    @moduledoc false

    def read_body(_conn, _opts) do
      raise Bandit.HTTPError, message: "Body read timeout", plug_status: :request_timeout
    end
  end

  defmodule InternalErrorBodyReader do
    @moduledoc false

    def read_body(_conn, _opts) do
      raise Bandit.HTTPError, message: "Internal error", plug_status: :internal_server_error
    end
  end

  test "parses request bodies with Plug.Parsers" do
    # Given
    opts =
      RequestBodyParserPlug.init(
        parsers: [:json],
        json_decoder: Phoenix.json_library()
      )

    conn =
      :post
      |> conn("/", ~s({"name":"tuist"}))
      |> put_req_header("content-type", "application/json")

    # When
    result = RequestBodyParserPlug.call(conn, opts)

    # Then
    assert result.body_params == %{"name" => "tuist"}
    refute result.halted
  end

  test "returns 408 when the request body read times out" do
    # Given
    opts =
      RequestBodyParserPlug.init(
        parsers: [:json],
        body_reader: {TimeoutBodyReader, :read_body, []},
        json_decoder: Phoenix.json_library()
      )

    conn =
      :post
      |> conn("/", ~s({"name":"tuist"}))
      |> put_req_header("content-type", "application/json")

    # When
    result = RequestBodyParserPlug.call(conn, opts)

    # Then
    assert result.status == 408
    assert result.resp_body == "Request Timeout"
    assert result.halted
  end

  test "reraises non-timeout Bandit HTTP errors" do
    # Given
    opts =
      RequestBodyParserPlug.init(
        parsers: [:json],
        body_reader: {InternalErrorBodyReader, :read_body, []},
        json_decoder: Phoenix.json_library()
      )

    conn =
      :post
      |> conn("/", ~s({"name":"tuist"}))
      |> put_req_header("content-type", "application/json")

    # When/Then
    assert_raise Bandit.HTTPError, "Internal error", fn ->
      RequestBodyParserPlug.call(conn, opts)
    end
  end
end
