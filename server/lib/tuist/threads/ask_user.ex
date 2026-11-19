defmodule Tuist.Threads.AskUser do
  @moduledoc "A replay-safe question whose wait and answer belong to the thread, not the session process."
  use Condukt.Tool

  alias Tuist.Threads
  alias Tuist.Threads.Cards
  alias Uniq.UUID

  @impl true
  def name(_opts), do: "ask_user"

  @impl true
  def description(_opts) do
    """
    Ask the person to choose between two to five concrete options when their decision is needed to continue.
    The thread waits durably, then this call returns their selected option_id and text, or status cancelled.
    Set allow_other to accept a free-text answer too. A dismissed question grants no permission to act.
    """
  end

  @impl true
  def parameters(_opts) do
    %{
      type: "object",
      properties: %{
        question: %{type: "string", minLength: 1, maxLength: 500},
        options: %{
          type: "array",
          minItems: 2,
          maxItems: 5,
          items: %{
            type: "object",
            properties: %{
              id: %{type: "string", pattern: "^[a-zA-Z0-9_-]{1,40}$"},
              label: %{type: "string", minLength: 1, maxLength: 300}
            },
            required: ["id", "label"],
            additionalProperties: false
          }
        },
        allow_other: %{type: "boolean"}
      },
      required: ["question", "options", "allow_other"],
      additionalProperties: false
    }
  end

  @impl true
  def replay_safe?, do: true

  @impl true
  def call(args, context) do
    run = context.opts[:run]
    request_id = UUID.uuid5(:oid, "ask_user:#{run.id}:#{context.tool_call_id}")

    with {:ok, question} <- validate(args) do
      existing = Threads.user_question(run, request_id)
      source = if is_nil(existing) and Cards.available?(), do: Cards.build_decision(question), else: {:ok, nil}

      with {:ok, source} <- source,
           {:ok, message} <- Threads.ask_user(run, request_id, question, source) do
        case message.decision do
          %{"status" => "pending"} -> {:park, args, timeout: to_timeout(day: 1)}
          result -> {:ok, JSON.encode!(Map.take(result, ["status", "answer"]))}
        end
      end
    end
  end

  @impl true
  def wake(:timeout, args, context), do: call(args, context)

  def validate(%{"question" => question, "options" => options, "allow_other" => other})
      when is_binary(question) and is_list(options) and is_boolean(other) do
    if text?(question, 500) and valid_options?(options) do
      {:ok,
       %{"question" => question, "options" => Enum.map(options, &Map.take(&1, ["id", "label"])), "allow_other" => other}}
    else
      invalid()
    end
  end

  def validate(_), do: invalid()

  defp valid_options?(options) do
    length(options) in 2..5 and
      Enum.all?(options, fn
        %{"id" => id, "label" => label} when is_binary(id) and is_binary(label) ->
          Regex.match?(~r/\A[a-zA-Z0-9_-]{1,40}\z/, id) and text?(label, 300)

        _ ->
          false
      end) and
      length(Enum.uniq_by(options, & &1["id"])) == length(options) and
      length(Enum.uniq_by(options, & &1["label"])) == length(options)
  end

  defp text?(text, max), do: String.valid?(text) and String.trim(text) != "" and String.length(text) <= max

  defp invalid,
    do:
      {:error,
       "Give a question (1–500 characters), two to five distinct options with short unique ids and labels (1–300 characters), and allow_other."}
end
