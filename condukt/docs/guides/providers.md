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

## Preparing images before persistence

ReqLLM transports image attachments but does not decode or resize them.
Enable `:image_policy` to prepare user attachments, `Read` image results,
and MCP image content blocks before Condukt records them in conversation
history or its run journal. Without a policy, Condukt preserves its existing
image behavior. Subagents inherit their parent's policy.

```elixir
MyApp.Agent.start_link(
  image_policy: [
    prepare: {MyApp.ImagePreparer, :prepare, []},
    max_width: 1600,
    max_height: 1600,
    max_base64_bytes: 1_048_576,
    max_input_bytes: 20_971_520,
    max_pixels: 40_000_000,
    max_images: 8,
    max_total_base64_bytes: 4_194_304,
    timeout: 5_000
  ]
)
```

These are example application limits, not provider defaults. Choose limits
for the model and request envelope you use. `:max_images` and
`:max_total_base64_bytes` apply across retained user attachments and per MCP
response; `:max_base64_bytes` caps each encoded output, including base64
expansion. Other tool image results have a per-image budget. This does not
cap all bytes or tokens in conversation history.
Condukt also limits preparation attempts to the remaining image count per
turn (or the response count for MCP); rejected candidates consume an attempt.

Implement the MFA in your host application with a decoder such as Image/Vix.
Condukt supplies decoded input bytes and the policy map, followed by the
MFA's extra arguments. The map includes a signature-derived `:media_type`.
Your callback must:

* Decode the complete image and reject corrupt or truncated inputs. Check
  source dimensions against `:max_pixels` before allocating decoded pixels.
* Apply EXIF orientation, then fit within both dimension limits without
  cropping or upscaling. Use the oriented dimensions for aspect ratio.
* Encode within the output byte budget and return
  `{:ok, bytes, "image/png", %{width: width, height: height}}` (PNG, JPEG,
  GIF and WebP signatures are supported), or `{:error, reason}`. Define an
  animation policy in the host rather than returning unbounded frames.

Condukt checks base64, input size, output signature, reported dimensions and
encoded size. It trusts your decoder for pixel correctness and actual
dimensions. Signature sniffing alone cannot validate an image. You do not
need a native image dependency when you leave the policy unset.

Condukt runs each preparation in a separate task. Exceptions, exits, invalid
returns and timeouts omit that image with a fixed note; sibling text and
acceptable images remain. Condukt also adds a note for a changed image so
the model uses coordinates in the prepared image. Callback errors do not
enter conversation text, though task crash logs may contain them. Do not
include secrets in those errors. Set decoder memory/resource limits too:
killing a task cannot guarantee cancellation of native work already running.
`Read` still reads the file before preparation, so enforce filesystem or
transport limits at ingress to avoid that initial allocation.

Tool images continue to use JSON text, not provider vision blocks. Condukt
prepares known structured image results after tool hooks, and MCP blocks
before rendering them as text. It does not search arbitrary strings or
nested application payloads for base64 images. Custom runtimes receive the
prepared prompt and attachments but remain responsible for validating any
history they return.

See [image history and recovery](sessions-and-persistence.md#image-history-and-recovery)
before enabling a policy on existing sessions.

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
