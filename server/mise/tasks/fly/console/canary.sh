#!/usr/bin/env bash
# mise description="Opens an Elixir console with the remote canary server"

(cd server && flyctl ssh console --app tuist-cloud-canary --pty -C "/app/bin/tuist remote")
