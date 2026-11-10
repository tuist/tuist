# Changelog

All notable changes to this project will be documented in this file.
## [1.14.0] - 2026-10-29

### Features

- add safe-boundary background compaction


## [1.13.2] - 2026-10-28

### Bug Fixes

- preserve provider reasoning across tool turns


## [1.13.1] - 2026-10-24

### Bug Fixes

- compact context before each native model turn


## [1.13.0] - 2026-08-28

### Features

- propagate trace context


## [1.12.0] - 2026-08-27

### Features

- cap the output tokens of one call with :max_tokens


## [1.11.0] - 2026-08-17

### Features

- rewrite the terminal agent in Elixir and retire the Rust and WebAssembly builds


## [1.10.1] - 2026-08-16

### Bug Fixes

- let the deployer manage the namespaced Issuer


## [1.10.0] - 2026-08-15

### Features

- serve the site at condukt.dev, and let the deploy create the release


## [1.9.1] - 2026-08-15

### Changes

- pin the deploy toolchain in mise.toml with a lockfile


## [1.9.0] - 2026-08-14

### Features

- merge plasma into condukt under a single brand


## [1.8.0] - 2026-08-11

### Features

- Support stable session store keys


## [1.7.0] - 2026-06-12

### Bug Fixes

- detect plain one-shot agent modules



### Features

- retry transient provider failures


## [1.6.2] - 2026-05-28

### Bug Fixes

- support agents without operations


## [1.6.1] - 2026-05-28

### Bug Fixes

- return synchronous exit errors


## [1.6.0] - 2026-05-27

### Bug Fixes

- make MCP subagents provider-safe



### Features

- add microsandbox sandbox backend


## [1.5.1] - 2026-05-19

### Changes

- terminal identity, Elixir purple, repositioned copy


## [1.5.0] - 2026-05-18

### Features

- add Sandbox.Net egress audit + policy with runtime decider


## [1.4.1] - 2026-05-13

### Bug Fixes

- Fix blog social card title wrapping


## [1.4.0] - 2026-05-13

### Features

- add agent runtime boundary


## [1.3.0] - 2026-05-12

### Features

- add HTTP route helpers for operations (Plug + Phoenix)


## [1.2.1] - 2026-05-12

### Changes

- Generate post social cards


## [1.2.0] - 2026-05-12

### Features

- scope Condukt sandbox and store by session id, route project context through sandbox


## [1.1.0] - 2026-05-11

### Features

- add Kubernetes sandbox


## [1.0.0] - 2026-05-11

### Bug Fixes

- drop missing priv dir from Hex package files



### Changes

- redesign workflows around a single self-contained .star file



### Features

- Add client-side MCP support


## [0.21.0] - 2026-05-08

### Features

- session-scoped assigns merged from tool returns


## [0.20.0] - 2026-05-08

### Features

- emit :llm_turn events around each LLM round-trip


## [0.19.0] - 2026-05-08

### Features

- include tool args, status, and result in tool_call events


## [0.18.0] - 2026-05-07

### Features

- identify sessions with UUIDv7 and propagate through events


## [0.17.0] - 2026-05-07

### Bug Fixes

- encode image messages as ReqLLM ContentPart structs



### Features

- One-shot agent execution


## [0.16.5] - 2026-05-04

### Bug Fixes

- promote releases after engine assets publish


## [0.16.4] - 2026-05-04

### Bug Fixes

- skip website tooling in engine builds


## [0.16.3] - 2026-05-04

### Bug Fixes

- build macos engine assets natively


## [0.16.2] - 2026-05-04

### Bug Fixes

- package cross-platform engine releases


## [0.16.1] - 2026-05-04

### Bug Fixes

- build engine release assets on compatible runner


## [0.16.0] - 2026-05-04

### Features

- Add subagent delegation support


## [0.15.1] - 2026-05-03

### Changes

- Remove workflows build flag


## [0.15.0] - 2026-05-03

### Features

- Add session secret providers


## [0.14.2] - 2026-05-03

### Bug Fixes

- publish Hex packages from prod env


- make release env assertion valid YAML


## [0.14.1] - 2026-05-03

### Bug Fixes

- load precompiled NIFs for Hex consumers


## [0.14.0] - 2026-05-03

### Features

- Add sandbox abstraction with Local and Virtual (bashkit NIF) backends


- Add anonymous runtime workflows


## [0.13.1] - 2026-05-03

### Changes

- Deploy website to Cloudflare Pages project condukt-website


## [0.13.0] - 2026-05-03

### Features

- Add a blog to the marketing site


## [0.12.0] - 2026-05-02

### Features

- Add Eleventy marketing site with Cloudflare Workers deploy


## [0.11.0] - 2026-05-02

### Features

- typed operations on agent modules


## [0.10.0] - 2026-05-02

### Features

- pluggable outbound redactor with regex default


## [0.9.0] - 2026-05-02

### Features

- add pluggable conversation compactor


## [0.8.0] - 2026-05-02

### Features

- add scoped command tool


## [0.7.2] - 2026-05-02

### Bug Fixes

- polish release note formatting


## [0.7.1] - 2026-05-02

### Bug Fixes

- remove redundant release title


## [0.7.0] - 2026-05-02

### Features

- load project instructions from local files


## [0.6.1] - 2026-04-29

### Bug Fixes

- update repo references after move to tuist org


## [0.6.0] - 2026-03-25

### Features

- Claude Opus 4.6 (1M context) <noreply@anthropic.com>


## [0.5.0] - 2026-03-24

### Features

- Add Ollama provider support


## [0.4.1] - 2026-03-19

### Changes

- Revert "Add runtime provider interface"

This reverts commit dd40a9469ddebed5d4c0317cdf6ce4a7682098b7.


## [0.4.0] - 2026-03-19

### Features

- Add runtime provider interface


## [0.3.0] - 2026-03-19

### Features

- Add remote runtime investigation


## [0.2.0] - 2026-03-19

### Changes

- Avoid rescue in session stores


- Split session store tests by backend


- Document built-in session stores


- Format disk store tests



### Features

- Add pluggable session stores


- Add disk session store tests


- Use ExUnit tmp_dir in disk store tests


## [0.1.0] - 2026-03-15

### Bug Fixes

- Fix Livebook input flow


- Fix Livebook select option values


- Fix streaming and Livebook output



### Changes

- Initial commit


- Read, Bash, Edit, Write
- Telemetry integration for observability
- Extended thinking support

Inspired by Pi coding agent but implemented natively in Elixir
for better integration with OTP applications.


- Replace custom provider layer with ReqLLM


- Finalize agent configuration and tooling


- Align edit tool with Pi semantics


- Revert "Allow Bash to provision Nix packages"

This reverts commit e4587abb7c07ef7c08a021154744b21e30194afd.


- Remove empty application callback


- Install Kino in Livebook playground



### Features

- Add MuonTrap command execution guidance


- Use MuonTrap and normalize tool parameter naming


- Add read tool image coverage


- Allow Bash to provision Nix packages


- Rename package to Helmsman


- Add local Livebook playground


- Make Livebook playground Kino-compatible


- Use ReqLLM reasoning effort option


- Adapt session to current ReqLLM responses


- Preserve tool calls in ReqLLM context


- Use JSON decoder in Livebook


- automate hex.pm publishing


<!-- generated by git-cliff -->
