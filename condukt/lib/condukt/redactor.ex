defmodule Condukt.Redactor do
  @moduledoc """
  Behaviour for redacting sensitive data before it is sent to an LLM provider.

  A redactor is invoked on outbound message text — user input and tool results
  — right before the conversation is handed to the LLM. Assistant output and the
  system prompt are left untouched: the LLM has already seen its own prior
  responses, and the system prompt is authored by the developer.

  Redactors are configured per session at `start_link/1` via the `:redactor`
  option. The value can be a module or a `{module, opts}` tuple. When `nil`
  (the default), no redaction is performed.

      MyApp.Agent.start_link(redactor: Condukt.Redactors.Regex)

      MyApp.Agent.start_link(redactor: {Condukt.Redactors.Regex, patterns: my_patterns})

  ## Implementing a redactor

      defmodule MyApp.Redactor do
        @behaviour Condukt.Redactor

        @impl true
        def redact(text, _opts) do
          String.replace(text, ~r/\\bsecret-[a-z0-9]+\\b/, "[REDACTED]")
        end
      end

  Redaction in this version is outbound-only: the original text remains in the
  session's stored history. Each turn re-runs the redactor on the messages that
  are about to be sent, so secrets never leave the BEAM process.
  """

  alias Condukt.Message

  @doc """
  Returns `text` with sensitive substrings replaced.

  `opts` is the keyword list provided alongside the module in a
  `{module, opts}` spec, or `[]` when the spec is a bare module.
  """
  @callback redact(text :: String.t(), opts :: keyword()) :: String.t()

  @doc """
  Applies a redactor spec to a single string.

  The spec is a module implementing the behaviour, a `{module, opts}` tuple, a
  list of redactor specs, or `nil`. Returns `text` unchanged when `spec` is
  `nil` or an empty list.
  """
  def apply(nil, text), do: text
  def apply(module, text) when is_atom(module), do: module.redact(text, [])
  def apply({module, opts}, text) when is_atom(module) and is_list(opts), do: module.redact(text, opts)

  def apply(specs, text) when is_list(specs) do
    Enum.reduce(specs, text, fn spec, acc -> __MODULE__.apply(spec, acc) end)
  end

  @doc """
  Returns `messages` with redaction applied to user input and tool results.

  Assistant messages and any non-textual content blocks are returned unchanged.
  Tool result content that is not a binary is JSON-encoded before redaction so
  embedded secrets in structured output are still caught.
  """
  def redact_messages(nil, messages), do: messages
  def redact_messages([], messages), do: messages
  def redact_messages(spec, messages), do: Enum.map(messages, &redact_message(spec, &1))

  defp redact_message(spec, %Message{role: :user, content: content} = msg) when is_binary(content) do
    %{msg | content: __MODULE__.apply(spec, content)}
  end

  defp redact_message(spec, %Message{role: :tool_result, content: content} = msg) when is_binary(content) do
    %{msg | content: __MODULE__.apply(spec, content)}
  end

  defp redact_message(spec, %Message{role: :tool_result, content: content} = msg) do
    %{msg | content: __MODULE__.apply(spec, JSON.encode!(content))}
  end

  defp redact_message(_spec, %Message{} = msg), do: msg
end
