#!/usr/bin/env bash
#MISE description="Opens an Elixir console with the remote production server"

flyctl ssh console --app tuist-cloud --pty -C "/app/bin/tuist remote"
