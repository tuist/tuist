defmodule TuistEx.Analytics.RelayTest do
  use ExUnit.Case, async: true

  import ExUnit.CaptureIO

  alias TuistEx.Analytics.Relay

  defp relay(chunks, encoding) do
    {:ok, device} = StringIO.open("", encoding: encoding)
    assert %Relay{} = Enum.into(chunks, Relay.new(device))
    {:ok, {_input, output}} = StringIO.close(device)
    output
  end

  test "relays a multi-byte character split across chunks" do
    <<first::binary-size(2), rest::binary>> = "한글\n"

    assert relay([first, rest], :unicode) == "한글\n"
  end

  test "relays a character split over more than two chunks" do
    <<a::binary-size(1), b::binary-size(1), c::binary>> = "😀 done\n"

    assert relay([a, b, c], :unicode) == "😀 done\n"
  end

  test "replaces bytes that are not UTF-8 instead of raising" do
    assert relay([<<"a", 0xFF, "b\n">>], :unicode) == "a�b\n"
  end

  test "writes the bytes of an unfinished character when the output ends" do
    <<first::binary-size(2), _rest::binary>> = "한"

    assert relay(["ok ", first], :unicode) == "ok �"
  end

  test "passes bytes through untouched to a device in latin1 mode" do
    <<first::binary-size(2), rest::binary>> = "한글\n"

    assert relay([first, rest], :latin1) == "한글\n"
  end

  test "relays a subprocess's output" do
    output =
      capture_io(fn ->
        assert {%Relay{}, 0} = System.cmd("printf", ["\\355\\225\\234\\n"], into: Relay.new())
      end)

    assert output == "한\n"
  end
end
