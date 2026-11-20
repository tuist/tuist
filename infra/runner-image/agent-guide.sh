#!/bin/bash
# Writes the guide for coding agents that work on this Mac, generated from what
# the image holds, and the instruction files that point agents at it.
#
#   agent-guide.sh write <guide path>   prints nothing; writes the guide
#   agent-guide.sh link <home>          writes the pointers in <home>
#
# The image build runs `write` as runner after everything else is installed,
# so the versions it lists are the ones a sandbox boots with.
set -euo pipefail

xcodes() {
  local app version build
  for app in /Applications/Xcode*.app; do
    [ -d "$app" ] && [ ! -L "$app" ] || continue
    version=$(/usr/libexec/PlistBuddy -c 'Print :CFBundleShortVersionString' "$app/Contents/Info.plist" 2>/dev/null || echo unknown)
    build=$(/usr/libexec/PlistBuddy -c 'Print :ProductBuildVersion' "$app/Contents/version.plist" 2>/dev/null || echo unknown)
    echo "- Xcode $version ($build) at \`$app\`"
  done
}

simulators() {
  # `-- iOS 26.5 --` headers, then one device per line; keep names only.
  xcrun simctl list devices available | awk '
    /^-- / { sub(/^-- /, ""); sub(/ --$/, ""); runtime = $0; next }
    /^    / && runtime != "" {
      name = $0; sub(/^ +/, "", name); sub(/ \([0-9A-F]+-[0-9A-F-]+\) \([^()]*\) *$/, "", name)
      devices[runtime] = devices[runtime] (devices[runtime] == "" ? "" : ", ") name
      if (!(runtime in seen)) { seen[runtime] = 1; order[++n] = runtime }
    }
    END { for (i = 1; i <= n; i++) printf "- %s: %s\n", order[i], devices[order[i]] }'
}

tools() {
  local tool line=""
  for tool in brew mise git git-lfs gh jq yq xcbeautify swiftlint swiftformat fastlane pod carthage xcodes ruby node python3; do
    command -v "$tool" >/dev/null 2>&1 && line="${line:+$line, }\`$tool\`"
  done
  echo "$line"
}

write() {
  local out=$1 tuist_version
  tuist_version=$(/opt/tuist/cli/bin/tuist version 2>/dev/null | tail -1)
  cat >"$out" <<EOF
# Working on this Mac

This is a Tuist macOS VM: a sandbox when an agent or a person created it, or a
CI runner that runs one job and shuts down. This guide was generated from the
image when it was built.

## The machine

- macOS $(sw_vers -productVersion) ($(sw_vers -buildVersion)), Apple silicon. You are \`runner\`, with passwordless \`sudo\`.
$(xcodes)
- The active Xcode is \`$(xcode-select -p)\`. A sandbox keeps the Xcode it booted with; another Xcode needs another sandbox.

Simulators, by runtime (\`xcrun simctl list devices available\`; boot one with
\`xcrun simctl boot "<name>"\`):

$(simulators)

Other tools: $(tools).

## Where the code is

- Repositories live in \`/Users/runner/work/<name>\`, a volume with its own
  quota. \`tuist sandbox sync\` mirrors a local Git worktree to
  \`/Users/runner/work/<name>\`, where \`<name>\` comes from its \`origin\`
  remote, and prints that path as \`root\`.
- **A ready snapshot**: when a sandbox is created for a repository whose
  account prepares Macs for it, it boots from that repository's snapshot for
  its Xcode. The default branch is already cloned to
  \`/Users/runner/work/<name>\`, the account's macOS setup script has run there
  (dependencies installed, project generated, the scheme built), and Xcode's
  DerivedData is warm. The first sync sends only the files that differ from that
  commit, so builds are incremental. Without a snapshot the Mac boots bare and
  \`/Users/runner/work\` is empty.
- Sync is one way: the agent edits files where it runs, and the next sync
  overwrites changes to tracked files made here. Files Git ignores, such as build
  products, stay.

## Tuist

- Tuist $tuist_version is installed. \`tuist\` runs a repository's own version
  when it pins one through mise (\`mise.toml\`, \`.tool-versions\`), installing
  it on first use, and this one otherwise. Commands started with
  \`tuist sandbox exec\` have both on \`PATH\`; in another shell, use
  \`\$HOME/.local/share/mise/shims\` and then \`/opt/tuist/cli/bin\`.
- Each command started with \`tuist sandbox exec\` gets \`TUIST_URL\`, the
  in-rack \`TUIST_CACHE_ENDPOINT\` and a short-lived \`TUIST_OIDC_TOKEN\`, so
  Tuist 4.218.0 or later signs in to the account's cache on its own. Don't
  copy Tuist credentials onto the Mac. With 4.215.0 to 4.217.x, run
  \`tuist auth login\` first in the same command.

## Driving it from another machine

An agent that runs elsewhere, such as on Linux, uses the Tuist CLI there with
\`--account <account>\`:

- \`tuist sandbox sync <id> --json\` before every command; it returns \`root\`.
- \`tuist sandbox exec <id> --cwd <root> -- '<command>'\` streams output and
  exits with the command's status. Start long builds in the background with
  output in a log file, then read the log.
- \`tuist sandbox cp <id>:<path> <local-path>\` copies results back, such as a
  screenshot (\`xcrun simctl io booted screenshot /tmp/shot.png\`), an
  \`.xcresult\` bundle or a built app.
- Run only the builds and tests the user asked for, and delete the sandbox
  (\`tuist sandbox delete <id> --yes\`) when the task is done. An idle sandbox
  pauses, and the next command resumes it.
- A sandbox created this way lives until its \`expires_at\`
  (\`tuist sandbox show <id>\`), two hours from creation or its last resume by
  default. Then its running commands are cancelled and it is paused and
  archived, keeping its files. Before a long build, extend it with
  \`tuist sandbox extend <id> --lifetime-minutes <n>\` (at most a day).

## Builds

- Build into a known directory: \`xcodebuild ... -derivedDataPath build/dd\`,
  then \`xcrun simctl install booted build/dd/Build/Products/Debug-iphonesimulator/<App>.app\`.
- Pipe long output through \`xcbeautify\` or \`tail\`.
EOF
}

link() {
  local home=$1 pointer
  pointer="This Mac carries a guide for agents at /opt/tuist/agent-guide.md: its Xcode and simulators, where the repository is, what a ready snapshot means, and how Tuist and its cache work here. Read it before working on this machine."
  mkdir -p "$home/.claude" "$home/.codex" "$home/.config/amp"
  # Claude Code reads ~/.claude/CLAUDE.md and every CLAUDE.md above the working
  # directory, and inlines `@` imports.
  printf '%s\n\n@/opt/tuist/agent-guide.md\n' "$pointer" >"$home/.claude/CLAUDE.md"
  printf '%s\n\n@/opt/tuist/agent-guide.md\n' "$pointer" >"$home/CLAUDE.md"
  # Codex reads ~/.codex/AGENTS.md; Amp ~/.config/amp/AGENTS.md; others walk up
  # to ~/AGENTS.md.
  for file in "$home/.codex/AGENTS.md" "$home/.config/amp/AGENTS.md" "$home/AGENTS.md"; do
    printf '%s\n' "$pointer" >"$file"
  done
}

case "${1:-}" in
  write) write "$2" ;;
  link) link "$2" ;;
  *) echo "usage: $0 write <guide path> | link <home>" >&2; exit 64 ;;
esac
