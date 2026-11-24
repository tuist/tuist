defmodule LuftServer.Threads.CardsTest do
  use ExUnit.Case, async: true

  alias LuftServer.Threads.Cards

  test "untrusted source may only statically import the trusted local kit" do
    assert :ok =
             Cards.check_source(
               ~s|import { mount, Title } from "./luft"; mount(() => <Title>Hello</Title>);|
             )

    for source <- [
          ~s(import value from "/etc/passwd";),
          ~s(import value from "nsh";),
          ~s|import("./luft")|,
          ~s|require("./luft")|,
          ~s(import /* bypass */ value from "./luft";),
          String.duplicate("x", 65_537)
        ] do
      assert {:error, _} = Cards.check_source(source)
    end
  end

  test "layout checks every open and ignores content confined by a scroll view" do
    trace = """
    ── open(first)
    Create { id: 2, kind: VStack }
    Insert { parent: 1, child: 2 }
    Frame { id: 2, x: 0, y: 0, w: 320, h: 120 }
    ── open(second)
    Create { id: 3, kind: VStack }
    Insert { parent: 1, child: 3 }
    Frame { id: 3, x: 0, y: 0, w: 600, h: 140 }
    """

    assert {:error, _} = Cards.fits(trace, 120)
    assert :ok = Cards.fits(trace, 240)

    scroll = """
    ── open(scroll)
    Create { id: 2, kind: Scroll }
    Create { id: 3, kind: VStack }
    Insert { parent: 1, child: 2 }
    Insert { parent: 2, child: 3 }
    Frame { id: 2, x: 0, y: 0, w: 320, h: 120 }
    Frame { id: 3, x: 0, y: 0, w: 320, h: 900 }
    """

    assert :ok = Cards.fits(scroll, 120)
  end
end
