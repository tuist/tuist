#!/usr/bin/env bash
#MISE description="Opens an Elixir console with the remote canary server"

flyctl ssh console --app tuist-cloud-canary --pty -C "/app/bin/tuist remote"
