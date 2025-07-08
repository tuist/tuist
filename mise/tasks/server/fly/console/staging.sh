#!/usr/bin/env bash
# mise description="Opens an Elixir console with the remote staging server"

(cd server && flyctl ssh console --app tuist-cloud-staging --pty -C "/app/bin/tuist remote")
