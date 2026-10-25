defmodule TuistEx.Analytics.ExUnitPatch do
  @moduledoc false

  # Swaps a module of ExUnit's for a proxy, the way Mimic swaps a module it
  # copies: the original is compiled again from its debug info under another
  # name, and the proxy delegates every function to it but the ones given,
  # which go to another module. ExUnit has no option for what
  # `ExcludeTestIds` and `MutedFailures` change, so they patch it this way.

  @doc """
  Swaps `module` for a proxy. `original` names the copy of the module the
  proxy delegates to, and `{target, functions}` the functions that go to
  `target` instead. `check` runs once the copy is loaded and before the
  proxy is: anything but `:ok` leaves the module as it was.
  """
  def swap(module, original, {target, functions}, check) do
    with {^module, binary, path} <- :code.get_object_code(module),
         {:ok, forms} <- forms(module, binary),
         :ok <- load(original, path, rename(forms, module, original)),
         :ok <- check.(),
         :ok <- load(module, path, proxy(module, original, target, functions)) do
      :ok
    else
      {:error, reason} -> {:error, reason}
      other -> {:error, other}
    end
  end

  @doc """
  Whether `ExUnit.Runner` calls the given function, which a proxy must stand
  in for to change what the runner does.
  """
  def runner_calls?(mfa) do
    with {:module, ExUnit.Runner} <- Code.ensure_loaded(ExUnit.Runner),
         {ExUnit.Runner, binary, _path} <- :code.get_object_code(ExUnit.Runner),
         {:ok, {ExUnit.Runner, [imports: imports]}} <- :beam_lib.chunks(binary, [:imports]) do
      mfa in imports
    else
      _ -> false
    end
  end

  def installed?(module), do: function_exported?(module, :__tuist_ex_original__, 0)

  @doc """
  Puts ExUnit's own module back.
  """
  def restore(module, original) do
    if installed?(module) do
      :code.purge(module)
      {:module, ^module} = :code.load_file(module)
      :code.purge(original)
      :code.delete(original)
      :code.purge(original)
    end

    :ok
  end

  defp forms(module, binary) do
    with {:ok, {^module, [debug_info: {:debug_info_v1, backend, data}]}} <-
           :beam_lib.chunks(binary, [:debug_info]),
         {:ok, forms} <- backend.debug_info(:erlang_v1, module, data, []) do
      {:ok, forms}
    else
      _ -> {:error, :no_debug_info}
    end
  end

  defp rename(forms, module, original) do
    Enum.map(forms, fn
      {:attribute, anno, :module, ^module} -> {:attribute, anno, :module, original}
      form -> form
    end)
  end

  defp proxy(module, original, target, functions) do
    anno = :erl_anno.new(0)
    exports = Enum.reject(original.module_info(:exports), &(elem(&1, 0) == :module_info))

    delegations =
      for {name, arity} = function <- exports do
        to = if function in functions, do: target, else: original
        args = for index <- 1..arity//1, do: {:var, anno, :"Arg#{index}"}
        call = {:call, anno, {:remote, anno, {:atom, anno, to}, {:atom, anno, name}}, args}
        {:function, anno, name, arity, [{:clause, anno, args, [], [call]}]}
      end

    marker =
      {:function, anno, :__tuist_ex_original__, 0,
       [{:clause, anno, [], [], [{:atom, anno, original}]}]}

    [
      {:attribute, anno, :module, module},
      {:attribute, anno, :export, [{:__tuist_ex_original__, 0} | exports]},
      marker | delegations
    ]
  end

  defp load(module, path, forms) do
    with {:ok, ^module, binary} <- :compile.forms(forms, [:binary, :return_errors]),
         :code.purge(module),
         {:module, ^module} <- :code.load_binary(module, path, binary) do
      :ok
    else
      error -> {:error, {:load, module, error}}
    end
  end
end
