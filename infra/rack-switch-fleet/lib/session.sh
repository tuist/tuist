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
#
# Bash also deletes the coprocess array the moment the coprocess is reaped, so a
# connection that fails fast turns every ${SWITCH[0]} into an unbound variable
# rather than a read error. Every access goes through switch_alive, and ssh's
# own diagnostics go to SWITCH_LOG so there is something to print once the
# descriptors are gone. It deletes SWITCH_PID with it, so that is guarded too.
#
# Writing to a coprocess whose ssh has already exited raises SIGPIPE, and a
# shell killed by SIGPIPE does not run its EXIT trap. That is worse than a lost
# error message: the logout never happens, the switch keeps the session, and
# enough of those wedge its SSH daemon. SIGPIPE is therefore ignored for as long
# as a session is open, so a write to a dead ssh fails as an error that the
# logout path can still run after.

SWITCH_PAGER='Press any key to continue (Q to quit)'
SWITCH_ADDRESS=""
# SWITCH and SWITCH_PID are set by `coproc SWITCH` below, not here.
SWITCH_PID=""
SWITCH_BUFFER=""
SWITCH_OUTPUT=""
SWITCH_LOG=""
# Set per command by switch_run_confirm and cleared straight after. Nothing is
# ever auto-confirmed: a command that asks "(Y/N)" and was not run through
# switch_run_confirm just waits out its timeout, which is the safe direction.
SWITCH_ANSWER=""
SWITCH_CONFIRM=$'(Y/N)'
# How the last session ended: "logout" if ssh exited on its own after being told
# to, "killed" if it had to be signalled. A killed client can leave the switch
# holding a half-open connection, which is one candidate explanation for the
# connection budget and would be this tool's fault rather than the firmware's.
# FLEET_DEBUG_SESSIONS=1 prints it.
SWITCH_CLOSED_BY=""
# Switches reached through another machine rather than directly, by management
# address: an ssh destination that relays the connection. The rack's edge node
# is one, for a switch whose only uplink is its management port. Filled in by
# the caller from the site definition.
declare -gA SWITCH_JUMPS=()


# False once the coprocess is gone, which bash signals by deleting the array.
switch_alive() { [ -n "${SWITCH[0]:-}" ]; }

switch_open() {
  local address="$1" user="$2" key="$3" jump relay=()
  SWITCH_ADDRESS="$address"
  jump="${SWITCH_JUMPS[$address]:-}"
  # The relay authenticates as the operator to the jump host, never with the
  # switch key, which stays on this machine.
  [ -n "$jump" ] && relay=(-o "ProxyCommand=ssh -o BatchMode=yes -o ConnectTimeout=10 -W %h:%p $jump")

  SWITCH_LOG="$(mktemp)"
  trap '' PIPE
  coproc SWITCH {
    ssh -tt "${relay[@]}" \
      -i "${key/#\~/$HOME}" \
      -o IdentitiesOnly=yes \
      -o IdentityAgent=none \
      -o KexAlgorithms=+diffie-hellman-group14-sha1 \
      -o HostKeyAlgorithms=+ssh-rsa \
      -o PubkeyAcceptedAlgorithms=+ssh-rsa \
      -o StrictHostKeyChecking=accept-new \
      -o BatchMode=yes \
      -o ConnectTimeout=10 \
      "$user@$address" 2>"$SWITCH_LOG"
  }
  # The banner drain is allowed to time out; what matters is whether ssh is
  # still there afterwards.
  switch_drain 8 || true
  if ! switch_alive || ! kill -0 "${SWITCH_PID:-}" 2>/dev/null; then
    echo "error: $address accepted no session." >&2
    if [ -s "$SWITCH_LOG" ]; then
      sed 's/^/       ssh: /' "$SWITCH_LOG" >&2
    else
      echo "       ssh said nothing${SWITCH_BUFFER:+, the switch said: $SWITCH_BUFFER}" >&2
    fi
    echo "       If it answers ping but not SSH its session table is wedged; the web UI" >&2
    echo "       still works and a reboot clears it." >&2
    switch_close
    return 1
  fi
  switch_run enable
}

# Read until the prompt has been quiet for a moment, answering the pager.
# What the switch printed is left in SWITCH_BUFFER.
#
# Returns 0 only when the switch came back to a prompt, which is the only
# evidence that it finished the command. 1 means the session ended underneath
# us and 2 means it never answered. Both used to return 0 with an empty buffer,
# so a `copy tftp startup-config` that never happened read as a success and the
# run went on to reboot the switch.
switch_drain() {
  local timeout="${1:-120}" deadline character tail status scan=""
  SWITCH_BUFFER=""
  switch_alive || return 1
  deadline=$(( SECONDS + timeout ))
  while (( SECONDS < deadline )); do
    switch_alive || return 1
    # `status` is read explicitly rather than from $? after an `if`: an `if`
    # whose condition is false and which has no `else` exits 0, so the timeout
    # read as success and the drain returned an empty buffer the moment the
    # switch took longer than one interval to answer.
    status=0
    IFS= read -r -N1 -t 0.4 character <&"${SWITCH[0]}" || status=$?
    if (( status > 0 && status <= 128 )); then return 1; fi
    if (( status == 0 )); then
      SWITCH_BUFFER+="$character"
      # The pager is detected on a separate window, never by editing the
      # transcript: the prompt is what tells the normaliser that the padding
      # spaces after it are an erased line rather than indentation.
      scan+="$character"
      if [[ "$scan" == *"$SWITCH_PAGER"* ]]; then
        scan=""
        switch_alive && { printf ' ' 1>&"${SWITCH[1]}" 2>/dev/null || true; }
      elif [[ -n "$SWITCH_ANSWER" && "$scan" == *"$SWITCH_CONFIRM"* ]]; then
        scan=""
        switch_write "$SWITCH_ANSWER" || true
        SWITCH_ANSWER=""
      elif (( ${#scan} > 200 )); then
        scan="${scan: -100}"
      fi
      continue
    fi
    tail="${SWITCH_BUFFER##*$'\n'}"
    tail="${tail//$'\r'/}"
    # `ber1-tor-b#`, and also `ber1-tor-b(config)#` and `ber1-tor-b(config-if)#`.
    # Leaving the parenthesised modes out meant every command `apply` sends ran
    # the full timeout waiting for a prompt that was already on screen.
    [[ "$tail" =~ [A-Za-z0-9._-]+(\([A-Za-z0-9-]+\))?[#\>][[:space:]]*$ ]] && return 0
  done
  return 2
}

switch_write() {
  switch_alive || { echo "error: $SWITCH_ADDRESS closed the session" >&2; return 1; }
  printf '%s\r\n' "$1" 1>&"${SWITCH[1]}" 2>/dev/null && return 0
  echo "error: $SWITCH_ADDRESS closed the session while being sent '$1'" >&2
  switch_report_ssh
  return 1
}

# What ssh itself said, which is the only account of why a session ended.
switch_report_ssh() {
  [ -n "$SWITCH_LOG" ] && [ -s "$SWITCH_LOG" ] || return 0
  sed 's/^/       ssh: /' "$SWITCH_LOG" >&2
}

switch_run() {
  local command="$1" timeout="${2:-120}" drained=0
  # Checked rather than left to errexit: every caller in fleet.sh uses `||`,
  # which disables errexit for everything this function does.
  if ! switch_write "$command"; then
    SWITCH_OUTPUT=""
    return 1
  fi
  switch_drain "$timeout" || drained=$?
  SWITCH_OUTPUT="$SWITCH_BUFFER"
  case "$drained" in
    1) echo "error: $SWITCH_ADDRESS ended the session during '$command'" >&2
       switch_report_ssh
       return 1;;
    2) echo "error: $SWITCH_ADDRESS never finished '$command' (no prompt within ${timeout}s)" >&2
       return 1;;
  esac
  if [[ "$SWITCH_OUTPUT" == *"Error:"* || "$SWITCH_OUTPUT" == *"Bad command"* \
     || "$SWITCH_OUTPUT" == *"Failed to"* ]]; then
    echo "error: $SWITCH_ADDRESS rejected '$command':" >&2
    printf '%s\n' "$SWITCH_OUTPUT" | grep -E 'Error|Bad command|Failed to' >&2 || true
    return 1
  fi
}

# A command that asks for confirmation before doing something. The answer is
# named at the call site so nothing is ever confirmed on the switch's say-so.
switch_run_confirm() {
  local command="$1" answer="$2" timeout="${3:-120}" status=0
  SWITCH_ANSWER="$answer"
  switch_run "$command" "$timeout" || status=$?
  SWITCH_ANSWER=""
  return $status
}

# End the session for real. See the session-table note at the top.
switch_close() {
  if [ -z "${SWITCH_PID:-}" ] && ! switch_alive; then
    trap - PIPE
    if [ -n "$SWITCH_LOG" ]; then rm -f "$SWITCH_LOG"; SWITCH_LOG=""; fi
    return 0
  fi
  # Always try, even when the session looks dead: leaving a session open is what
  # wedges the switch, and `logout` is the only thing that frees one.
  if switch_alive; then
    switch_write 'end'    >/dev/null 2>&1 || true
    switch_drain 5 || true
    switch_write 'logout' >/dev/null 2>&1 || true
    switch_drain 5 || true
  fi
  local waited=0
  while [ -n "${SWITCH_PID:-}" ] && kill -0 "${SWITCH_PID:-}" 2>/dev/null && (( waited < 5 )); do
    sleep 1; waited=$(( waited + 1 ))
  done
  if [ -n "${SWITCH_PID:-}" ] && kill -0 "${SWITCH_PID:-}" 2>/dev/null; then
    SWITCH_CLOSED_BY="killed after ${waited}s"
    kill -9 "${SWITCH_PID:-}" 2>/dev/null || true
  else
    SWITCH_CLOSED_BY="logout"
  fi
  [ -n "${FLEET_DEBUG_SESSIONS:-}" ] && echo "session ended: $SWITCH_CLOSED_BY" >&2
  wait "${SWITCH_PID:-}" 2>/dev/null || true
  SWITCH_PID=""
  trap - PIPE
  if [ -n "$SWITCH_LOG" ]; then rm -f "$SWITCH_LOG"; SWITCH_LOG=""; fi
}
