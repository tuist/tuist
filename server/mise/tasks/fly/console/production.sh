#!/usr/bin/env bash
# mise description="Opens an Elixir console with the remote production server"

(cd server && flyctl ssh console --app tuist-cloud --pty -C "/app/bin/tuist remote")
