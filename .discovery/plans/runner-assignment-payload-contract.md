# Runner assignment payload contract

## Goal

Define the exact payload shape that `server/` should hand to a Tart-based host worker.

This contract is designed to map directly onto the validated worker primitives in `/runners/scripts`.

## Recommended payload shape

```json
{
  "assignment_id": "asg_01JX...",
  "base_vm": "tuist-sequoia-base",
  "cache": {
    "hostname": "tuist-01-test-cache.par.runners.tuist.dev",
    "host_gateway": "192.168.64.1",
    "private_ip": "172.16.16.4"
  },
  "github": {
    "registration_mode": "registration_token",
    "runner_name": "tuist-assignment-asg_01JX...",
    "work_folder": "_work",
    "labels": [
      "self-hosted",
      "macos",
      "apple-silicon",
      "scaleway",
      "xcode-26-2"
    ],
    "registration": {
      "token": "<short-lived token>"
    }
  },
  "job": {
    "repository_full_handle": "tuist/tuist",
    "workflow_job_id": 12345,
    "workflow_run_id": 67890,
    "workflow_name": "CLI Self-Hosted",
    "job_name": "Lint"
  },
  "timeouts": {
    "vm_boot_seconds": 180,
    "job_seconds": 3600
  }
}
```

## Required fields

- `assignment_id`
- `base_vm`
- `cache.hostname`
- `github.registration_mode`
- `github.runner_name`
- `job.workflow_job_id`

## `registration_mode`

### `registration_token`

Payload shape:

```json
{
  "github": {
    "registration_mode": "registration_token",
    "registration": {
      "token": "<token>"
    }
  }
}
```

### `jit_config`

Payload shape:

```json
{
  "github": {
    "registration_mode": "jit_config",
    "registration": {
      "jit_config": "<opaque jit config blob>"
    }
  }
}
```

## How the current worker uses it

Validated scripts:

- `run-tart-assignment-from-payload.nu`
- `stage-tart-assignment-registration.nu`

Current behavior:

- create disposable VM from `base_vm`
- boot it and prepare cache access
- write runtime registration artifacts into `/var/run/tuist/` inside the guest

## Runtime files staged in the guest

For `registration_token` mode:

- `/var/run/tuist/github-runner-config.json`
- `/var/run/tuist/github-runner.token`

For `jit_config` mode:

- `/var/run/tuist/github-runner-config.json`
- `/var/run/tuist/github-runner.jitconfig`

## Validation status

The payload contract is now concrete and validated against the test host worker scripts.

Validated result:

- disposable clone created successfully
- cache bootstrap succeeded inside the clone
- registration artifacts were staged inside `/var/run/tuist/`

Observed staged files:

- `/var/run/tuist/github-runner-config.json`
- `/var/run/tuist/github-runner.token`

This means the payload contract is ready to drive the future `server/` assignment API.
