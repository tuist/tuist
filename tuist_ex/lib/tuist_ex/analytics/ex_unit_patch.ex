defmodule TuistEx.Analytics.ExUnitPatch do
  @moduledoc false

  # Replaces an ExUnit module, for the rest of this VM, with one whose given
  # functions are tuist_ex's and whose other functions delegate to ExUnit's
  # own code, compiled from the module's debug info under another name. The
  # replacement's definitions call that copy to do what ExUnit did.

  @doc """
  Replaces `module`: `definitions` (quoted) define the `overrides`, a list
  of `{name, arity}`, and may call `original`, ExUnit's code; `marker`
  names a function only the replacement exports. A module already replaced
  is left alone; one that doesn't export every override isn't replaced,
  since ExUnit then works in a way the definitions don't know. Returns
  `:ok` or `:error`, never raises.
  """
  def wrap(module, original, marker, overrides, definitions) do
    Code.ensure_loaded(module)

    cond do
      function_exported?(module, marker, 0) ->
        :ok

      not Enum.all?(overrides, fn {name, arity} -> function_exported?(module, name, arity) end) ->
        :error

      true ->
        with {:ok, exports} <- keep_original(module, original) do
          replace(module, original, marker, overrides, definitions, exports)
        end
    end
  rescue
    _ -> :error
  end

  defp keep_original(module, original) do
    with {^module, beam, _path} <- :code.get_object_code(module),
         {:ok, {^module, [debug_info: {:debug_info_v1, backend, data}]}} <-
           :beam_lib.chunks(beam, [:debug_info]),
         {:ok, forms} <- backend.debug_info(:erlang_v1, module, data, []),
         forms =
           Enum.map(forms, fn
             {:attribute, anno, :module, ^module} -> {:attribute, anno, :module, original}
             form -> form
           end),
         {:ok, ^original, binary} <- :compile.forms(forms, [:binary, :return_errors]),
         {:module, ^original} <- :code.load_binary(original, ~c"tuist_ex", binary) do
      {:ok,
       Enum.reject(original.module_info(:exports), &(elem(&1, 0) in [:module_info, :__info__]))}
    else
      _ -> :error
    end
  end

  defp replace(module, original, marker, overrides, definitions, exports) do
    delegates =
      for {name, arity} <- exports, {name, arity} not in overrides do
        args = Macro.generate_arguments(arity, __MODULE__)

        quote do
          def unquote(name)(unquote_splicing(args)),
            do: unquote(original).unquote(name)(unquote_splicing(args))
        end
      end

    quoted =
      quote do
        defmodule unquote(module) do
          @moduledoc false
          def unquote(marker)(), do: true
          unquote(definitions)
          unquote_splicing(delegates)
        end
      end

    previous = Code.get_compiler_option(:ignore_module_conflict)
    Code.put_compiler_option(:ignore_module_conflict, true)

    try do
      Code.compile_quoted(quoted)
      :ok
    after
      Code.put_compiler_option(:ignore_module_conflict, previous)
    end
  end
end
