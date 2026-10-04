import Config

config :logger, level: :info

# Releases run on a read-only filesystem. Refresh the bundled timezone data
# through dependency updates and redeploys, not writes into the running release.
config :tzdata, autoupdate: :disabled
