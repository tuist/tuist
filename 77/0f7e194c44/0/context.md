# Session Context

## User Prompts

### Prompt 1

Can you list the Tuist projects?

### Prompt 2

[Request interrupted by user for tool use]

### Prompt 3

I noticed when you use the list_projects tool from the Tuist mcp it hangs. Can you investigate why that's the case? The tuist mcp is at https://tuist.dev/mcp

### Prompt 4

How does Hermes recommend solving this?

### Prompt 5

Change the server to return JSON instead. I think in the case of those tools we don't need to stream the responses

### Prompt 6

But locally I used a real connection where I ran the http server locally

### Prompt 7

I want something very simple. I'm very surprised I'm the only one running into this. That Hermes package seems very matured

### Prompt 8

Can you test this e2e using curl locally?

### Prompt 9

But why does it fail in production? Can you curl against production?

### Prompt 10

➜  tuist3 git:(main) ✗ curl -s -D /tmp/mcp_h -X POST https://tuist.dev/mcp \
    -H "Content-Type: application/json" \
    -H "Accept: application/json, text/event-stream" \
    -H "Authorization: Bearer $TOKEN" \
    -d '{"jsonrpc":"2.0","id":1,"method":"initialize","params":{"protocolVersion":"2025-03-26","capabilities":{},"clientInfo":{"name":"curl-test","version":"1.0"}}}' \
    --max-time 10 && echo
{"error":"invalid_token","error_description":"Missing or invalid access token."}

### Prompt 11

The claude code (you) are also authenticated...

### Prompt 12

[Request interrupted by user for tool use]

### Prompt 13

You are hanging

### Prompt 14

Can you open a PR with this?

### Prompt 15

You didn't write tests for your work. Also make the Elixir code more eloquent and not that nested

### Prompt 16

[Request interrupted by user]

### Prompt 17

actually the issue that you mention suggest to use this fork instead:
https://github.com/zoedsoupe/anubis-mcp

Can you change the dependency, and check if the issue has been fixed there

### Prompt 18

Did you change the dependency? Since the one that we use, hermes is not maintained anymore

### Prompt 19

This session is being continued from a previous conversation that ran out of context. The summary below covers the earlier portion of the conversation.

Analysis:
Let me go through the conversation chronologically:

1. User started by connecting to the Tuist MCP and trying to list projects - it hung.
2. User asked me to investigate why the Tuist MCP at https://tuist.dev/mcp hangs when calling list_projects.
3. I explored the server-side MCP implementation:
   - Router forwards /mcp to Hermes.Ser...

