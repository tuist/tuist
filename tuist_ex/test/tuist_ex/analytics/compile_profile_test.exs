defmodule TuistEx.Analytics.CompileProfileTest do
  use ExUnit.Case, async: true

  alias TuistEx.Analytics.CompileProfile

  # A profile of its own per test: nothing here installs the compiler tracer
  # or touches standard error, which `CompileProfileInstallTest` covers.
  setup do
    %{profile: CompileProfile.new()}
  end

  defp no_source(_module), do: nil

  defp env(file, module \\ nil),
    do: %{__ENV__ | file: Path.expand(file), module: module, function: nil}

  test "reports compile time, waits, and the file each wait was on", %{profile: profile} do
    CompileProfile.record(profile, {:on_module, <<>>, :none}, env("lib/macros.ex", Demo.Macros))
    CompileProfile.record(profile, {:on_module, <<>>, :none}, env("lib/greeter.ex", Demo.Greeter))

    assert CompileProfile.record_profile_output(
             profile,
             "[profile]    306ms compiling +      0ms waiting while compiling lib/macros.ex\n"
           )

    assert CompileProfile.record_profile_output(
             profile,
             "[profile]     70ms compiling +    333ms waiting for module Demo.Macros while compiling lib/greeter.ex\n" <>
               "[profile]                    |     12ms waiting for struct Ecto.Changeset while compiling lib/greeter.ex\n"
           )

    assert [greeter, macros] = CompileProfile.files(profile, &no_source/1)

    assert macros == %{
             path: "lib/macros.ex",
             start_offset_ms: nil,
             compile_duration_ms: 306,
             wait_duration_ms: 0,
             modules: ["Demo.Macros"],
             waits: [],
             dependencies: []
           }

    assert greeter.compile_duration_ms == 70
    assert greeter.wait_duration_ms == 345

    assert greeter.waits == [
             %{
               kind: "module",
               module: "Demo.Macros",
               path: "lib/macros.ex",
               duration_ms: 333,
               start_offset_ms: nil
             },
             %{
               kind: "struct",
               module: "Ecto.Changeset",
               path: nil,
               duration_ms: 12,
               start_offset_ms: nil
             }
           ]
  end

  test "places each file and each wait on the build's clock", %{profile: profile} do
    profile = CompileProfile.new(1_000)

    CompileProfile.record(profile, :start, env("lib/macros.ex"), 1_010)
    CompileProfile.record(profile, :start, env("lib/greeter.ex"), 1_020)

    CompileProfile.record(
      profile,
      {:on_module, <<>>, :none},
      env("lib/macros.ex", Demo.Macros),
      1_400
    )

    CompileProfile.record(profile, :stop, env("lib/macros.ex"), 1_405)
    CompileProfile.record(profile, :stop, env("lib/greeter.ex"), 1_460)

    CompileProfile.record_profile_output(
      profile,
      "[profile]     70ms compiling +    333ms waiting for module Demo.Macros while compiling lib/greeter.ex\n" <>
        "[profile]                    |     12ms waiting for struct Ecto.Changeset while compiling lib/greeter.ex\n"
    )

    assert [greeter, macros] = CompileProfile.files(profile, &no_source/1)

    assert macros.start_offset_ms == 10
    assert greeter.start_offset_ms == 20

    # The wait on Demo.Macros ends when that module becomes available (400ms
    # in), so it started 333ms earlier. Nothing says when Ecto.Changeset
    # became available, so that wait has no position.
    assert [
             %{module: "Demo.Macros", start_offset_ms: 67},
             %{module: "Ecto.Changeset", start_offset_ms: nil}
           ] =
             greeter.waits
  end

  test "falls back to the tracer's timing for a file the compiler printed nothing for", %{
    profile: profile
  } do
    CompileProfile.record(profile, :start, env("lib/a.ex"))
    CompileProfile.record(profile, {:on_module, <<>>, :none}, env("lib/a.ex", A))
    CompileProfile.record(profile, :stop, env("lib/a.ex"))

    assert [
             %{
               path: "lib/a.ex",
               modules: ["A"],
               wait_duration_ms: 0,
               waits: [],
               compile_duration_ms: duration
             }
           ] =
             CompileProfile.files(profile, &no_source/1)

    assert duration >= 0
  end

  test "reports the work around the files as steps on the build's clock", %{profile: profile} do
    profile = CompileProfile.new(1_000)

    CompileProfile.record(
      profile,
      {:on_module, <<>>, :none},
      env("lib/greeter.ex", Demo.Greeter),
      1_100
    )

    CompileProfile.record_profile_output(
      profile,
      "[profile] Finished cycle resolution in 0ms\n",
      1_500
    )

    CompileProfile.record_profile_output(
      profile,
      "[profile] Finished compilation cycle of 4 modules in 500ms\n",
      1_500
    )

    CompileProfile.record_profile_output(
      profile,
      "[profile] Finished writing modules to disk in 20ms\n",
      1_520
    )

    CompileProfile.record_profile_output(
      profile,
      "[profile] Finished after compile callback in 65ms\n",
      1_585
    )

    CompileProfile.record_profile_output(
      profile,
      "[profile] Type checked Demo.Greeter in 30ms\n",
      1_620
    )

    CompileProfile.record_profile_output(profile, "[profile] Type checked Demo in 0ms\n", 1_620)

    CompileProfile.record_profile_output(
      profile,
      "[profile] Finished group pass check of 4 modules in 35ms\n",
      1_625
    )

    CompileProfile.compiler_finished(profile, :erlang, 1_010)
    CompileProfile.compiler_finished(profile, :elixir, 1_630)
    CompileProfile.compiler_finished(profile, :app, 1_642)

    assert CompileProfile.steps(profile) == [
             %{
               category: "write",
               title: "Writing modules to disk",
               path: nil,
               start_offset_ms: 500,
               duration_ms: 20
             },
             %{
               category: "other",
               title: "After compile callback",
               path: nil,
               start_offset_ms: 520,
               duration_ms: 65
             },
             %{
               category: "type_check",
               title: "Type checking Demo.Greeter",
               path: "lib/greeter.ex",
               start_offset_ms: 590,
               duration_ms: 30
             },
             %{
               category: "compiler",
               title: "mix compile.app",
               path: nil,
               start_offset_ms: 630,
               duration_ms: 12
             }
           ]
  end

  test "falls back to the whole type checking pass when the compiler does not report modules", %{
    profile: profile
  } do
    profile = CompileProfile.new(1_000)

    CompileProfile.record_profile_output(
      profile,
      "[profile] Finished group pass check of 4 modules in 35ms\n",
      1_625
    )

    assert [
             %{
               category: "type_check",
               title: "Type checking",
               start_offset_ms: 590,
               duration_ms: 35
             }
           ] =
             CompileProfile.steps(profile)
  end

  test "reports the project files each file depends on, and how strongly", %{profile: profile} do
    macros = env("lib/macros.ex", Demo.Macros)
    greeter = env("lib/greeter.ex", Demo.Greeter)
    in_function = %{greeter | function: {:hello, 1}}

    CompileProfile.record(profile, :start, macros)
    CompileProfile.record(profile, :start, greeter)
    CompileProfile.record(profile, {:on_module, <<>>, :none}, macros)
    CompileProfile.record(profile, {:on_module, <<>>, :none}, greeter)

    # A macro call needs the module at compile time, however often and
    # wherever it is also called at runtime.
    CompileProfile.record(profile, {:remote_function, [], Demo.Macros, :helper, 0}, in_function)
    CompileProfile.record(profile, {:remote_macro, [], Demo.Macros, :define, 1}, greeter)
    CompileProfile.record(profile, {:remote_macro, [], Demo.Macros, :define, 1}, greeter)
    # A struct is an export dependency; a call from a function body is runtime.
    CompileProfile.record(profile, {:struct_expansion, [], Demo.User, [:name]}, in_function)
    CompileProfile.record(profile, {:remote_function, [], Demo.Repo, :all, 1}, in_function)
    # Not project files: a dependency, and the module itself.
    CompileProfile.record(profile, {:remote_function, [], Enum, :map, 2}, in_function)
    CompileProfile.record(profile, {:remote_function, [], Demo.Greeter, :other, 0}, in_function)

    # Demo.User and Demo.Repo were compiled in an earlier run.
    project_source = fn
      Demo.User -> "lib/user.ex"
      Demo.Repo -> "lib/repo.ex"
      _ -> nil
    end

    assert [greeter_file, macros_file] = CompileProfile.files(profile, project_source)
    assert macros_file.dependencies == []

    assert greeter_file.dependencies == [
             %{path: "lib/macros.ex", kind: "compile"},
             %{path: "lib/repo.ex", kind: "runtime"},
             %{path: "lib/user.ex", kind: "export"}
           ]
  end

  test "treats non-profile output as something to pass through", %{profile: profile} do
    refute CompileProfile.record_profile_output(profile, "warning: variable \"x\" is unused\n")

    assert CompileProfile.record_profile_output(
             profile,
             "[profile] Finished cycle resolution in 0ms\n"
           )
  end
end
