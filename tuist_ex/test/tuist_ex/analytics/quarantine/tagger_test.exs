defmodule TuistEx.Analytics.Quarantine.TaggerTest do
  use ExUnit.Case, async: true

  # The tagger is a compiler tracer, global to the VM, and the modules it
  # tags register with ExUnit, so it runs in a VM of its own.
  test "skips a quarantined test without skipping same-named tests in other modules" do
    script = ~S"""
    alias TuistEx.Analytics.Quarantine

    defmodule UserTracer do
      def trace({:remote_macro, _meta, ExUnit.Case, :__using__, 1}, env) do
        IO.puts("user tracer saw #{inspect(env.module)}")
      end

      def trace(_event, _env), do: :ok
    end

    ExUnit.start(autorun: false)
    Code.put_compiler_option(:tracers, [UserTracer])

    policy =
      Quarantine.tag_skipped(%Quarantine{
        skipped:
          MapSet.new([
            {"CartTest", "", "flakes"},
            {"CartTest", "checkout", "flakes"},
            {"TemplatedTest", "", "flakes"},
            {"PropertyTest", "", "flakes"}
          ])
      })

    true = policy.tagged
    [TuistEx.Analytics.Quarantine.Tagger, UserTracer] = Code.get_compiler_option(:tracers)

    Code.compile_string(~S'''
    defmodule TemplateCase do
      use ExUnit.CaseTemplate
    end

    defmodule CartTest do
      use ExUnit.Case

      test "flakes", do: IO.puts("ran CartTest flakes")
      test "passes", do: IO.puts("ran CartTest passes")

      describe "checkout" do
        test "flakes", do: IO.puts("ran CartTest checkout flakes")
        test "passes", do: IO.puts("ran CartTest checkout passes")
      end
    end

    defmodule OtherTest do
      use ExUnit.Case, async: true

      test "flakes", do: IO.puts("ran OtherTest flakes")

      describe "checkout" do
        test "flakes", do: IO.puts("ran OtherTest checkout flakes")
      end
    end

    defmodule TemplatedTest do
      use TemplateCase, async: true

      test "flakes", do: IO.puts("ran TemplatedTest flakes")
      test "passes", do: IO.puts("ran TemplatedTest passes")
    end

    # Registered the way StreamData registers a `property`.
    defmodule PropertyTest do
      use ExUnit.Case

      name = ExUnit.Case.register_test(__MODULE__, __ENV__.file, __ENV__.line, :property, "flakes", [])
      def unquote(name)(_context), do: IO.puts("ran PropertyTest flakes")
    end
    ''')

    ExUnit.configure(exclude: ExUnit.Filters.parse(["tuist_quarantine:skipped"]), seed: 0)
    %{total: 9, excluded: 4, failures: 0} = ExUnit.run()
    """

    paths = Enum.flat_map(:code.get_path(), &["-pa", List.to_string(&1)])

    {output, status} =
      System.cmd(System.find_executable("elixir"), paths ++ ["-e", script],
        stderr_to_stdout: true
      )

    assert status == 0, output

    for ran <- [
          "CartTest passes",
          "CartTest checkout passes",
          "OtherTest flakes",
          "OtherTest checkout flakes",
          "TemplatedTest passes"
        ] do
      assert output =~ "ran #{ran}\n"
    end

    for skipped <- [
          "CartTest flakes",
          "CartTest checkout flakes",
          "TemplatedTest flakes",
          "PropertyTest flakes"
        ] do
      refute output =~ "ran #{skipped}\n"
    end

    for module <- ["CartTest", "OtherTest", "TemplatedTest"] do
      assert output =~ "user tracer saw #{module}\n"
    end
  end
end
