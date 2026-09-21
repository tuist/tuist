"""Turn switch CLI output into config text that can be compared with a render.

The CLI is a terminal, not an API. Its config dumps arrive wrapped in a pager
that erases itself with carriage returns, padded with `#` separators, and
bracketed by the echoed command and the next prompt. Normalising all of that
away is what turns "looks the same" into a diff worth acting on.
"""

import difflib
import re

PAGER = re.compile(r"Press any key to continue \(Q to quit\)")
ANSI = re.compile(r"\x1b\[[0-9;?]*[ -/]*[@-~]")
# This firmware follows the telnet convention of sending a bare CR as CR NUL, so
# every erased pager line arrives carrying a NUL that str.strip() does not touch.
CONTROL = re.compile(r"[\x00-\x08\x0b\x0c\x0e-\x1f\x7f]")
PROMPT = re.compile(r"^[\w.-]+[#>]\s*$")
BANNER = re.compile(r"^!")

# Lines the rendered state deliberately does not own, so a difference in them is
# not drift. The local admin login belongs to rack:prep-switch and 1Password.
UNMANAGED = (
    re.compile(r"^user name\b"),
    # `system-time ntp UTC <a> <b> 12 <c> <d> <e>` is what a live SX3832 holds, and
    # where the fetch interval sits among the servers is a guess until
    # `system-time ntp ?` is read off a unit. Rendering a guess would push it.
    re.compile(r"^system-time ntp\b"),
)


def scrub(line):
    """Drop the terminal's own bytes: escape sequences and stray controls."""
    return CONTROL.sub("", ANSI.sub("", line))


def apply_carriage_returns(line):
    """Collapse a physical line the way a terminal would, last write wins."""
    out = ""
    for segment in line.split("\r"):
        out = segment + out[len(segment):]
    return out


def strip_transcript(raw, command):
    """The config body out of a session transcript, without echo or prompt."""
    lines = [apply_carriage_returns(scrub(line)) for line in raw.split("\n")]
    start = None
    for index, line in enumerate(lines):
        if line.rstrip().endswith(command):
            start = index + 1
            break
    if start is None:
        raise ValueError(f"the transcript never echoed {command!r}; the session did not run it")
    body = []
    for line in lines[start:]:
        if PROMPT.match(line.strip()) and body:
            break
        body.append(line)
    return "\n".join(body)


def normalize(text):
    """Canonical, comparable form of a device configuration."""
    out = []
    for line in text.split("\n"):
        line = apply_carriage_returns(scrub(line))
        if PAGER.search(line):
            line = PAGER.sub("", line).lstrip()
        line = line.rstrip()
        stripped = line.strip()
        if not stripped or stripped == "#" or stripped == "end":
            continue
        if BANNER.match(stripped):
            continue
        if any(pattern.match(stripped) for pattern in UNMANAGED):
            continue
        out.append(line.rstrip())
    return out


def diff(desired, actual, desired_label, actual_label):
    """Unified diff of two configurations, empty when they agree."""
    return list(difflib.unified_diff(
        normalize(desired),
        normalize(actual),
        fromfile=desired_label,
        tofile=actual_label,
        lineterm="",
    ))


def redact(text):
    """A config safe to commit: the admin secret replaced, everything else kept."""
    out = []
    for line in text.split("\n"):
        line = apply_carriage_returns(scrub(line))
        if PAGER.search(line):
            line = PAGER.sub("", line).lstrip()
        line = line.rstrip()
        line = re.sub(r"(^\s*user name \S+ privilege \S+ secret \d+ ).*$",
                      r"\1<redacted, see 1Password>", line)
        out.append(line)
    while out and not out[-1].strip():
        out.pop()
    return "\n".join(out) + "\n"


def parse_blocks(text):
    """Configuration as {context: [command, ...]}, context "" being global."""
    blocks = {"": []}
    order = [""]
    context = ""
    for line in normalize(text):
        if not line.startswith((" ", "\t")):
            if line.startswith("interface ") or line.startswith("vlan "):
                context = line
                if context not in blocks:
                    blocks[context] = []
                    order.append(context)
                continue
            context = ""
        blocks.setdefault(context, [])
        blocks[context].append(line.strip())
    return [(c, blocks[c]) for c in order if blocks.get(c)]


def plan(desired, actual):
    """What to send to move `actual` to `desired`, and what a human must decide.

    Commands present on the device but absent from the render are reported
    rather than removed: turning an arbitrary line into its `no` form is a
    guess, and a wrong guess here costs a switch.
    """
    actual_blocks = dict(parse_blocks(actual))
    additions = []
    removals = []
    for context, commands in parse_blocks(desired):
        on_device = actual_blocks.get(context, [])
        missing = [c for c in commands if c not in on_device]
        if missing:
            additions.append((context, missing))
    desired_blocks = dict(parse_blocks(desired))
    for context, commands in parse_blocks(actual):
        wanted = desired_blocks.get(context)
        if wanted is None:
            continue
        for command in commands:
            if command not in wanted:
                removals.append((context, command))
    return additions, removals


def plan_commands(additions):
    """The apply plan as a flat command sequence, in CLI order."""
    out = ["configure"]
    for context, commands in additions:
        if context:
            out.append(context)
            out.extend(commands)
            out.append("exit")
        else:
            out.extend(commands)
    out.append("end")
    return out
