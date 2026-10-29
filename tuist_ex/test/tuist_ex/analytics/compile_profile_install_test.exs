defmodule TuistEx.Analytics.CompileProfileInstallTest do
  # Installing a profile changes the compiler's tracers and the process
  # registered as standard error, both of which belong to the whole VM.
  use ExUnit.Case, async: false

  alias TuistEx.Analytics.CompileProfile

  defp no_source(_module), do: nil

  test "routes the compiler's tracer to the installed profile, and stops on uninstall" do
    profile = CompileProfile.new()
    installation = CompileProfile.install(profile)
    env = %{__ENV__ | file: Path.expand("lib/traced.ex"), module: Traced, function: nil}

    assert CompileProfile in Code.get_compiler_option(:tracers)
    CompileProfile.trace(:start, env)
    CompileProfile.trace({:on_module, <<>>, :none}, env)
    CompileProfile.trace(:stop, env)

    :ok = CompileProfile.uninstall(installation)
    refute CompileProfile in Code.get_compiler_option(:tracers)

    # Nothing is installed any more, so this goes nowhere.
    CompileProfile.trace(:start, %{env | file: Path.expand("lib/late.ex")})

    assert [%{path: "lib/traced.ex", modules: ["Traced"]}] =
             CompileProfile.files(profile, &no_source/1)
  end

  test "hides profile lines but forwards everything else written to standard error" do
    output =
      ExUnit.CaptureIO.capture_io(:stderr, fn ->
        profile = CompileProfile.new()
        installation = CompileProfile.install(profile)

        IO.puts(
          :stderr,
          "[profile]      5ms compiling +      0ms waiting while compiling lib/x.ex"
        )

        IO.puts(:stderr, "a real warning")

        :ok = CompileProfile.uninstall(installation)

        assert [%{path: "lib/x.ex", compile_duration_ms: 5}] =
                 CompileProfile.files(profile, &no_source/1)
      end)

    assert output == "a real warning\n"
  end

  test "keeps the profile lines when the user asked for them" do
    output =
      ExUnit.CaptureIO.capture_io(:stderr, fn ->
        installation = CompileProfile.install(CompileProfile.new(), true)
        IO.puts(:stderr, "[profile] Finished cycle resolution in 0ms")
        :ok = CompileProfile.uninstall(installation)
      end)

    assert output == "[profile] Finished cycle resolution in 0ms\n"
  end
end
