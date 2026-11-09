# Providers

Condukt uses [ReqLLM](https://github.com/agentjido/req_llm) under the hood,
which means it speaks to 18+ LLM providers without bespoke client code. You
pick a provider by setting the `:model` option to a `provider:model`
identifier.

## Common identifiers

| Provider | Model format |
| -------- | ------------ |
| Anthropic | `anthropic:claude-sonnet-4-20250514` |
| OpenAI | `openai:gpt-4o` |
| Google Gemini | `google:gemini-2.0-flash` |
| Ollama | `ollama:llama3.2` |
| Groq | `groq:llama-3.3-70b-versatile` |
| OpenRouter | `openrouter:anthropic/claude-3.5-sonnet` |
| xAI | `xai:grok-3` |

See the [ReqLLM docs](https://hexdocs.pm/req_llm) for the full list and
their option semantics.

## API keys

ReqLLM auto discovers keys from the environment using the conventional
variable names:

```sh
export ANTHROPIC_API_KEY="sk-ant-..."
export OPENAI_API_KEY="sk-..."
export GROQ_API_KEY="..."
```

You can also pass `:api_key` per agent or set it under `config :condukt`.

## Overriding the base URL

`:base_url` lets you point at a self hosted gateway, an OpenAI compatible
server, or a local LLM:

```elixir
MyApp.LocalAgent.start_link(
  model: "openai:llama-3-70b",
  base_url: "http://localhost:11434/v1"
)
```

## Local models with Ollama

[ReqLLM](https://github.com/agentjido/req_llm) supports running prompts against
a local [Ollama](https://ollama.com) server. This is convenient for development,
evaluation, or offline use:

```elixir
MyApp.LocalAgent.start_link(
  model: "ollama:llama3.2",
  base_url: "http://localhost:11434"
)
```

## Choosing a model

A few rules of thumb:

* For production coding agents, the latest Anthropic Sonnet or OpenAI
  reasoning models tend to give the best tool use behaviour.
* For local development and tests, smaller open weights models on Ollama
  are fast and free.
* Lower the `:thinking_level` (`:low`, `:minimal`, `:off`) on cheap models
  that do not benefit from extended reasoning.

## Capping the output of one call

`:max_tokens` sets the ceiling on the output tokens a single call may produce.
It is left unset by default, so the provider's own default applies.

```elixir
MyApp.Agent.start_link(model: "openai:my-reasoning-model", max_tokens: 16_384)
```

Reasoning models are the case that makes this matter. They spend the output
budget thinking before writing a single character of the answer, so a ceiling
sized for the answer alone stops the response mid-thought and returns empty
content with a `length` finish reason rather than a short answer. If a model
answers with nothing at all, raise the ceiling before suspecting the prompt.

Not every gateway accepts `reasoning_effort` for turning that thinking off, so
a wider ceiling is sometimes the only lever available.

## Switching mid project

Because the model is a runtime option, you can swap it without touching the
agent module. This makes A/B comparisons easy:

```elixir
for model <- ["anthropic:claude-sonnet-4-20250514", "openai:gpt-4o"] do
  {:ok, agent} = MyApp.CodingAgent.start_link(model: model)
  {:ok, response} = Condukt.run(agent, "Refactor this function...")
  IO.puts("#{model}\n#{response}\n")
end
```
