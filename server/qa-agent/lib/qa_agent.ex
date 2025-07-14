defmodule QAAgent do
  @moduledoc """
  Agent that runs tasks using LangChain with available tools.
  """

  alias LangChain.Chains.LLMChain
  alias LangChain.ChatModels.ChatAnthropic
  alias LangChain.Message
  alias LangChain.Function
  alias LangChain.FunctionParam
  alias QAAgent.AxeTools

  @max_iterations 10

  @doc """
  Executes a task using LangChain with available tools.
  """
  def execute_task(config, prompt) do
    # Set up environment for Anthropic API
    Application.put_env(:langchain, :anthropic_key, config.api_key)

    # Create LLM
    llm =
      ChatAnthropic.new!(%{
        model: config.model,
        max_tokens: 2000
      })

    # Get available tools and convert to LangChain functions
    functions = get_langchain_functions(config.simulator_uuid)

    IO.puts("DEBUG: Created #{length(functions)} functions")

    # Create LLM chain and add tools
    case LLMChain.new!(%{llm: llm, max_retry_count: 10})
         |> LLMChain.add_message(Message.new_user!(prompt))
         |> LLMChain.add_tools(functions)
         |> LLMChain.run(mode: :while_needs_response) do
      {:ok, updated_chain} ->
        # Extract the final response
        response = extract_final_response(updated_chain)

        result = %{
          final_response: response,
          tool_calls: [],
          iterations: 1
        }

        {:ok, result}

      {:error, updated_chain, %LangChain.LangChainError{message: message}} ->
        {:error, "LLM chain execution failed: #{message}"}

      {:error, reason} ->
        {:error, "LLM chain execution failed: #{inspect(reason)}"}
    end
  end

  defp get_langchain_functions(simulator_uuid) do
    if simulator_uuid do
      AxeTools.get_tools()
      |> Enum.map(&convert_to_langchain_function(&1, simulator_uuid))
    else
      []
    end
  end

  defp convert_to_langchain_function(tool, simulator_uuid) do
    Function.new!(%{
      name: tool.name,
      description: tool.description,
      function: fn args, _context ->
        # Handle case where args might be nil
        args_map = if is_nil(args), do: %{}, else: args

        # Ensure simulator_uuid is in args if not provided
        args_with_uuid =
          case Map.get(args_map, "simulator_uuid") do
            nil when not is_nil(simulator_uuid) ->
              Map.put(args_map, "simulator_uuid", simulator_uuid)

            _ ->
              args_map
          end

        # Execute the tool function
        case tool.function.(args_with_uuid) do
          {:ok, result} -> {:ok, result.content}
          {:error, reason} -> {:ok, "Error: #{reason}"}
        end
      end
    })
  end

  defp convert_schema_to_params(%{properties: properties, required: required}, simulator_uuid) do
    properties
    |> Enum.map(fn {key, prop} ->
      key_str = to_string(key)

      # Auto-fill simulator_uuid if not provided and available
      default_value =
        if key_str == "simulator_uuid" && simulator_uuid do
          simulator_uuid
        else
          Map.get(prop, :default)
        end

      FunctionParam.new!(%{
        name: key_str,
        type: prop.type,
        description: prop.description,
        required: Enum.member?(required, key_str),
        default: default_value
      })
    end)
  end

  defp extract_final_response(chain) do
    case chain.last_message do
      nil -> "No response"
      last_message -> extract_content(last_message)
    end
  end

  defp extract_content(%Message{content: content}) when is_binary(content), do: content

  defp extract_content(%Message{content: content}) when is_list(content) do
    content
    |> Enum.map(fn
      %{type: :text, content: text} -> text
      item when is_binary(item) -> item
      item when is_map(item) -> Map.get(item, "text", Map.get(item, "content", ""))
    end)
    |> Enum.join("\n")
  end

  defp extract_content(content) when is_binary(content), do: content
  defp extract_content(_), do: "Response received"
end
