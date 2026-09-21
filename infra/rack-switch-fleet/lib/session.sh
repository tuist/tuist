# shellcheck shell=bash
# One switch's CLI over SSH, as a coprocess.
#
# Three properties of this firmware shape the whole file:
#
# - its SSH server negotiates only diffie-hellman-group14-sha1 and ssh-rsa,
#   which a current OpenSSH refuses by default. The failure reads like an
#   unreachable host, not like a rejected algorithm.
# - it allows one authentication attempt per connection and closes on the first
#   key the client offers, so the agent has to be taken out of the loop.
# - its session table does not reap the sessions a client abandons, and `exit`
#   from privileged mode drops to user EXEC while keeping the session. Only
#   `logout` ends one. Leaking sessions wedges the SSH daemon with the switch
#   still forwarding, still answering ping and still serving its web UI, so
#   nothing looks wrong while nobody can get in. Hence one session per run, and
#   a logout that runs even when the work failed.
#
# The coprocess file descriptors do not survive into a pipeline's subshell, so
# nothing here may be piped or captured with $(...). switch_run leaves what the
# switch printed in SWITCH_OUTPUT and the caller writes that to a file.

SWITCH_PAGER='Press any key to continue (Q to quit)'
SWITCH_ADDRESS=""
# SWITCH and SWITCH_PID are set by `coproc SWITCH` below, not here.
SWITCH_PID=""
SWITCH_BUFFER=""
SWITCH_OUTPUT=""

switch_open() {
  local address="$1" user="$2" key="$3"
  SWITCH_ADDRESS="$address"

  coproc SWITCH {
    ssh -tt \
      -i "${key/#\~/$HOME}" \
      -o IdentitiesOnly=yes \
      -o IdentityAgent=none \
      -o KexAlgorithms=+diffie-hellman-group14-sha1 \
      -o HostKeyAlgorithms=+ssh-rsa \
      -o PubkeyAcceptedAlgorithms=+ssh-rsa \
      -o StrictHostKeyChecking=accept-new \
      -o BatchMode=yes \
      -o ConnectTimeout=10 \
      "$user@$address" 2>&1
  }
  switch_drain 8
  if ! kill -0 "$SWITCH_PID" 2>/dev/null; then
    echo "error: $address accepted no session: ${SWITCH_BUFFER:-no output}" >&2
    echo "       if it answers ping but not SSH its session table is wedged; the web UI" >&2
    echo "       still works and a reboot clears it" >&2
    return 1
  fi
  switch_run enable
}

# Read until the prompt has been quiet for a moment, answering the pager.
# What the switch printed is left in SWITCH_BUFFER.
switch_drain() {
  local timeout="${1:-120}" deadline character tail status scan=""
  SWITCH_BUFFER=""
  deadline=$(( SECONDS + timeout ))
  while (( SECONDS < deadline )); do
    if IFS= read -r -N1 -t 0.4 character <&"${SWITCH[0]}"; then
      SWITCH_BUFFER+="$character"
      # The pager is detected on a separate window, never by editing the
      # transcript: the prompt is what tells the normaliser that the padding
      # spaces after it are an erased line rather than indentation.
      scan+="$character"
      if [[ "$scan" == *"$SWITCH_PAGER"* ]]; then
        scan=""
        printf ' ' >&"${SWITCH[1]}"
      elif (( ${#scan} > 200 )); then
        scan="${scan: -100}"
      fi
      continue
    fi
    status=$?
    (( status > 128 )) || return 0
    tail="${SWITCH_BUFFER##*$'\n'}"
    tail="${tail//$'\r'/}"
    [[ "$tail" =~ [A-Za-z0-9._-]+[#\>][[:space:]]*$ ]] && return 0
  done
  return 0
}

switch_write() { printf '%s\r\n' "$1" >&"${SWITCH[1]}"; }

switch_run() {
  local command="$1" timeout="${2:-120}"
  switch_write "$command"
  switch_drain "$timeout"
  SWITCH_OUTPUT="$SWITCH_BUFFER"
  if [[ "$SWITCH_OUTPUT" == *"Error:"* || "$SWITCH_OUTPUT" == *"Bad command"* ]]; then
    echo "error: $SWITCH_ADDRESS rejected '$command':" >&2
    printf '%s\n' "$SWITCH_OUTPUT" | grep -E 'Error|Bad command' >&2 || true
    return 1
  fi
}

# End the session for real. See the session-table note at the top.
switch_close() {
  [ -n "$SWITCH_PID" ] || return 0
  if kill -0 "$SWITCH_PID" 2>/dev/null; then
    switch_write 'end'    || true
    switch_drain 5 || true
    switch_write 'logout' || true
    switch_drain 5 || true
  fi
  local waited=0
  while kill -0 "$SWITCH_PID" 2>/dev/null && (( waited < 5 )); do
    sleep 1; waited=$(( waited + 1 ))
  done
  kill -9 "$SWITCH_PID" 2>/dev/null || true
  wait "$SWITCH_PID" 2>/dev/null || true
  SWITCH_PID=""
}
