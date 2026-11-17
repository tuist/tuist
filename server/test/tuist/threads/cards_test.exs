defmodule Tuist.Threads.CardsTest do
  use ExUnit.Case, async: true

  alias Tuist.Threads.Cards

  # `nsh test --trace` of a card whose root holds a scroll view with 384
  # points of content and a 96-point view below it, opened at 240 and then at
  # 100 points high (NSH 0.5.1, its `Command` lines left out).
  @trace """
  ✓ bundled Small.tsx (739 B in 1.7 ms)
  ── open(Small.tsx): 16 items
     LayoutDirection { rtl: false }
     Create { id: 2, kind: View }
     Create { id: 4, kind: Scroll }
     Create { id: 6, kind: View }
     Insert { parent: 4, child: 6, before: None }
     Insert { parent: 2, child: 4, before: None }
     Create { id: 8, kind: View }
     Insert { parent: 2, child: 8, before: None }
     Insert { parent: 1, child: 2, before: None }
     Frame { id: 2, x: 0, y: 0, w: 320, h: 240 }
     Frame { id: 4, x: 16, y: 16, w: 288, h: 112 }
     ScrollContent { id: 4, size: Size { width: 288pt, height: 384pt } }
     Frame { id: 6, x: 0, y: 0, w: 288, h: 384 }
     Frame { id: 8, x: 16, y: 128, w: 288, h: 96 }
  ✓ small.test.tsx › fits (104ms)
  ── open(Small.tsx): 17 items
     LayoutDirection { rtl: false }
     Create { id: 2, kind: View }
     Create { id: 4, kind: Scroll }
     Create { id: 6, kind: View }
     Insert { parent: 4, child: 6, before: None }
     Insert { parent: 2, child: 4, before: None }
     Create { id: 8, kind: View }
     Insert { parent: 2, child: 8, before: None }
     Insert { parent: 1, child: 2, before: None }
     Frame { id: 2, x: 0, y: 0, w: 320, h: 100 }
     Frame { id: 4, x: 16, y: 16, w: 288, h: 0 }
     ScrollContent { id: 4, size: Size { width: 288pt, height: 384pt } }
     Frame { id: 6, x: 0, y: 0, w: 288, h: 384 }
     Frame { id: 8, x: 16, y: 16, w: 288, h: 96 }
     Overflow { id: 2, extent: Some(Bounds { origin: Point { x: 0pt, y: 0pt }, size: Size { width: 320pt, height: 112pt } }) }
  ✓ small.test.tsx › overflows (101ms)
  """

  describe "fits/2" do
    test "content inside a scroll view may extend past the frame" do
      [fits, _overflows] = opens()
      assert Cards.fits(fits, 240) == :ok
    end

    test "content below the frame is refused with how tall it is" do
      [_fits, overflows] = opens()
      assert {:error, message} = Cards.fits(overflows, 100)
      assert message =~ "112 points tall at 320 points wide, but its frame is 100"
    end
  end

  describe "check_source/1" do
    test "a card may import nsh and its modules" do
      assert Cards.check_source(~s(import { mount, View } from "nsh";\nimport { Button } from 'nsh/base';)) == :ok
    end

    test "a card may not import anything else, which the bundler would read from this machine" do
      for specifier <- ["./data.json", "/etc/passwd", "nsh/../../secrets", "lodash", "node:fs"] do
        assert {:error, message} = Cards.check_source(~s(import x from "#{specifier}";)), specifier
        assert message =~ "may import only `nsh`"
      end

      assert {:error, _} = Cards.check_source(~s(export * from "./other";))
      assert {:error, _} = Cards.check_source(~s(import "./side-effect";))
    end

    test "a card may not load modules at run time" do
      for source <- [~s{const m = await import("nsh/base");}, "import.meta.glob('*')", ~s{require("fs")}] do
        assert {:error, message} = Cards.check_source(source), source
        assert message =~ "aren't available"
      end
    end
  end

  test "a comment between `import`/`from` and what follows is refused, which the bundler would still resolve" do
    for source <- [
          ~s(import data from /**/ "/etc/passwd";),
          ~s(import /**/ "/proc/1/environ";),
          ~s(import x from // c\n "./x";),
          "const m = import /**/ .meta;",
          ~s{const fs = require /**/ ("fs");}
        ] do
      assert {:error, _} = Cards.check_source(source), source
    end
  end

  # These run the real command line where it's installed (mise.toml), and
  # pass without checking anything where it isn't.
  describe "build/2 with NSH" do
    @card """
    import { mount, Text, View } from "nsh";
    function App() {
      return (<View class="flex-1 p-4"><Text>Slowest: TuistKit</Text></View>);
    }
    mount(App);
    """

    test "a card that fits is bundled" do
      if Cards.available?() do
        assert {:ok, bundle} = Cards.build(@card, "compact")
        assert bundle =~ "TuistKit"
      end
    end

    test "a card that logs without end is stopped at the output limit" do
      if Cards.available?() do
        flood =
          String.replace(
            @card,
            "mount(App);",
            ~s{for (let i = 0; i < 2000; i++) console.log("y".repeat(100000));\nmount(App);}
          )

        assert {:error, message} = Cards.build(flood, "compact")
        assert message =~ "wrote more than"
      end
    end
  end

  test "an unknown size is refused before anything runs" do
    assert {:error, message} = Cards.build("mount(App)", "huge")
    assert message =~ "compact, medium, tall"
  end

  defp opens do
    @trace
    |> String.split("── open(")
    |> tl()
    |> Enum.map(&("── open(" <> &1))
  end
end
