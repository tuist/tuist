# Smoke-tests Condukt.Sandbox.Virtual end-to-end against a real LLM.
#
# Usage:
#
#   FIREWORKS_API_KEY=fw_... mix run scripts/virtual_smoke_test.exs
#
# What it does:
#
# 1. Builds a transient agent that lists Read/Write/Edit/Bash/Glob/Grep tools.
# 2. Boots it with the bashkit-backed Virtual sandbox (in-memory FS).
# 3. Asks the model to do a small file-creation + read-back task.
# 4. Prints what each tool call did so we can eyeball that the Virtual
#    sandbox handled the writes/reads inside its in-memory FS.

defmodule SmokeAgent do
  use Condukt

  @impl Condukt
  def tools, do: Condukt.Tools.coding_tools()
end

api_key = System.fetch_env!("FIREWORKS_API_KEY")

# kimi-k2p6 isn't in ReqLLM's static catalog, so build the model struct
# directly. The :openai provider speaks the OpenAI-compatible REST API
# that Fireworks exposes; `base_url` redirects it to Fireworks' endpoint.
{:ok, model} =
  LLMDB.Model.new(%{
    id: "accounts/fireworks/models/kimi-k2p6",
    provider: :openai
  })

{:ok, agent} =
  SmokeAgent.start_link(
    api_key: api_key,
    base_url: "https://api.fireworks.ai/inference/v1",
    model: model,
    sandbox: Condukt.Sandbox.Virtual,
    load_project_instructions: false,
    system_prompt: """
    You are a coding agent operating inside an isolated sandbox. Use the
    provided tools to complete the user's task. Keep tool calls minimal.
    """
  )

prompt = """
Do the following inside the sandbox:

1. Write a file at `/tmp/note.txt` with the contents `hello virtual sandbox`.
2. Read it back.
3. Edit it to replace `virtual` with `bashkit`.
4. Read the final contents.

Then summarize what's in `/tmp/note.txt`.
"""

IO.puts("==> Running agent (sync)\n")

case Condukt.run(agent, prompt, max_turns: 8, timeout: 180_000) do
  {:ok, response} ->
    IO.puts("\n--- final response ---\n#{response}\n")

  {:error, reason} ->
    IO.puts("\n[error] #{inspect(reason)}")
end

IO.puts("\n==> Conversation history (tool calls + results):")

agent
|> Condukt.history()
|> Enum.each(fn msg ->
  IO.puts("--- #{msg.role} ---")

  content =
    case msg.content do
      blocks when is_list(blocks) ->
        Enum.map_join(blocks, "\n", &inspect/1)

      other ->
        inspect(other)
    end

  truncated =
    if String.length(content) > 600,
      do: String.slice(content, 0, 600) <> "...",
      else: content

  IO.puts(truncated)
end)
