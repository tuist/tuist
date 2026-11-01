defmodule TuistEx.Analytics.Quarantine.Tagger do
  @moduledoc false

  # Tags the tests Tuist skips with `tuist_quarantine: :skipped` while the
  # test files compile, so one `--exclude tuist_quarantine:skipped` leaves out
  # exactly those tests: an ExUnit name filter cannot say which module a
  # name belongs to. Installed as a compiler tracer, it needs nothing from
  # the test modules, whether they use `ExUnit.Case` directly or through a
  # case template.
  #
  # The tags go on before the module is compiled: an async module can start
  # running as soon as it is, too early to change what `__ex_unit__/0`
  # returns. ExUnit collects the tests in its internal `:ex_unit_tests`
  # attribute; `available?/0` tells whether this ExUnit still does.

  alias TuistEx.Analytics.ExUnitFormatter
  alias TuistEx.Analytics.Quarantine

  @skipped {__MODULE__, :skipped}

  def available? do
    with path when is_list(path) <- :code.which(ExUnit.Case),
         {:ok, {_module, [atoms: atoms]}} <- :beam_lib.chunks(path, [:atoms]) do
      List.keymember?(atoms, :ex_unit_tests, 1)
    else
      _ -> false
    end
  end

  @doc """
  Tags the given identities in every test module compiled from now on, next
  to the tracers already installed.
  """
  def install(skipped) do
    :persistent_term.put(@skipped, skipped)
    tracers = Code.get_compiler_option(:tracers)
    if __MODULE__ not in tracers, do: Code.put_compiler_option(:tracers, [__MODULE__ | tracers])
    :ok
  end

  # Added here, ahead of the `@before_compile` callback `use ExUnit.Case`
  # adds, so it runs first: callbacks run in the order they were added.
  def trace({:remote_macro, _meta, ExUnit.Case, :__using__, 1}, %{module: module})
      when module != nil do
    Module.put_attribute(module, :before_compile, __MODULE__)
    :ok
  end

  def trace(_event, _env), do: :ok

  defmacro __before_compile__(env) do
    skipped = :persistent_term.get(@skipped, MapSet.new())
    # Newest first, as an accumulated attribute reads.
    tests = Module.get_attribute(env.module, :ex_unit_tests)

    if is_list(tests) and Enum.any?(tests, &skipped?(skipped, &1)) do
      Module.delete_attribute(env.module, :ex_unit_tests)

      for test <- Enum.reverse(tests),
          do: Module.put_attribute(env.module, :ex_unit_tests, tag(skipped, test))
    end

    nil
  end

  defp tag(skipped, test) do
    if skipped?(skipped, test),
      do: %{test | tags: Map.put(test.tags, :tuist_quarantine, :skipped)},
      else: test
  end

  defp skipped?(skipped, %ExUnit.Test{} = test),
    do: MapSet.member?(skipped, Quarantine.identity(ExUnitFormatter.record(test)))

  defp skipped?(_skipped, _test), do: false
end
