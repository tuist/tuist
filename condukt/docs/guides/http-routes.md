# HTTP Routes

Module-defined agents and typed operations can be exposed as JSON HTTP
endpoints with `Condukt.Plug`.

Use an agent route when you want to run a normal `use Condukt` module as a
one-shot request handler. Use an operation route when you want a statically
declared entrypoint with input and output schemas.

## Agent routes

Agent routes run `Condukt.run(MyApp.Agent, prompt, opts)` for each HTTP
request. The request body can be a raw prompt string, a JSON string, or a JSON
object with an optional `"prompt"` string. If it is missing, the route's
`:prompt` option is used. If neither is provided, Condukt runs the agent with
an empty prompt.

```elixir
defmodule MyApp.AssistantAgent do
  use Condukt

  @impl true
  def system_prompt do
    "You are a helpful assistant for support requests."
  end
end
```

### Plug Router

```elixir
defmodule MyApp.Router do
  use Plug.Router

  plug Plug.Parsers, parsers: [:json], json_decoder: JSON
  plug :match
  plug :dispatch

  post "/assistant",
    to: Condukt.Plug,
    init_opts: [
      agent: MyApp.AssistantAgent,
      prompt: "Help with this support request.",
      run_opts: [timeout: 120_000]
    ]
end
```

Agent route request:

```text
Summarize the last customer message and suggest a reply.
```

Or as JSON:

```json
{
  "prompt": "Summarize the last customer message and suggest a reply."
}
```

Agent route response:

```json
{
  "ok": true,
  "result": "The customer is asking for..."
}
```

Use `:prompt_param` if the request uses a different field name:

```elixir
post "/assistant",
  to: Condukt.Plug,
  init_opts: [
    agent: MyApp.AssistantAgent,
    prompt_param: "message"
  ]
```

## Operation routes

Operation routes run `Condukt.Operation.run/4` for each HTTP request. The
request body must match the operation input schema, and the response contains
the validated structured output.

```elixir
defmodule MyApp.ReviewAgent do
  use Condukt

  operation :review_pr,
    input: %{
      type: "object",
      properties: %{
        repo: %{type: "string"},
        pr_number: %{type: "integer"}
      },
      required: ["repo", "pr_number"]
    },
    output: %{
      type: "object",
      properties: %{
        verdict: %{type: "string", enum: ["approve", "request_changes", "comment"]},
        summary: %{type: "string"}
      },
      required: ["verdict", "summary"]
    },
    instructions: "Review the pull request and return a verdict."
end
```

Each request runs the operation through Condukt's one-shot structured run path.
No conversation history is kept between HTTP requests.

### Plug Router

```elixir
defmodule MyApp.Router do
  use Plug.Router

  plug Plug.Parsers, parsers: [:json], json_decoder: JSON
  plug :match
  plug :dispatch

  post "/review-pr",
    to: Condukt.Plug,
    init_opts: [
      agent: MyApp.ReviewAgent,
      operation: :review_pr,
      run_opts: [timeout: 120_000]
    ]
end
```

If `conn.body_params` has not been fetched, `Condukt.Plug` reads and decodes
the request body itself.

### Request and response shape

Requests are JSON objects that match the operation input schema:

```json
{
  "repo": "tuist/condukt",
  "pr_number": 42
}
```

Successful responses use this envelope:

```json
{
  "ok": true,
  "result": {
    "verdict": "approve",
    "summary": "Looks good."
  }
}
```

Errors use this envelope:

```json
{
  "ok": false,
  "error": {
    "code": "invalid_input",
    "message": "..."
  }
}
```

Input validation failures return `422`, malformed JSON returns `400`, unknown
operations return `404`, and structured agent failures return `502` or `500`
depending on where the failure happened.

## Per-request run options

Use `:run_opts` to pass options to `Condukt.run/3` for agent routes or
`Condukt.Operation.run/4` for operation routes. The value can be a keyword list
or a one-arity function that receives the connection:

```elixir
post "/review-pr",
  to: Condukt.Plug,
  init_opts: [
    agent: MyApp.ReviewAgent,
    operation: :review_pr,
    run_opts: &MyApp.RouteOptions.condukt_run_opts/1
  ]
```

If the HTTP input should come from somewhere other than the JSON body, pass an
`:input` function. In router declarations, use remote captures rather than
anonymous functions because route options are stored at compile time:

```elixir
post "/repos/:owner/:repo/pulls/:number/review",
  to: Condukt.Plug,
  init_opts: [
    agent: MyApp.ReviewAgent,
    operation: :review_pr,
    input: &MyApp.RouteOptions.review_input/1
  ]
```

```elixir
defmodule MyApp.RouteOptions do
  def condukt_run_opts(conn) do
    [
      api_key: fetch_session_api_key(conn),
      timeout: 120_000
    ]
  end

  def review_input(conn) do
    %{
      "repo" => conn.path_params["owner"] <> "/" <> conn.path_params["repo"],
      "pr_number" => String.to_integer(conn.path_params["number"])
    }
  end
end
```
