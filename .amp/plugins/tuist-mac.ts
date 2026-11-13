// Tuist Mac: gives an Amp thread a macOS Tuist sandbox (Xcode, iOS simulators, Homebrew) for
// Apple-platform builds, tests and simulator screenshots, from a Linux orb or any machine that is
// not a Mac. It is a thin wrapper around the Tuist CLI (`tuist sandbox create`, `sync`, `exec`,
// `cp` and `delete`), which does the syncing and command streaming.
//
// Setup, including how to install this file as a workspace, personal or project plugin:
// https://tuist.dev/en/docs/guides/features/sandboxes/amp#remote-mac
//
// - Needs the Tuist CLI where Amp runs.
// - Authentication is the CLI's: in an orb of an Amp workspace connected to the Tuist account it
//   signs in on its own; otherwise `tuist auth login` or `TUIST_TOKEN`. TUIST_MAC_TOKEN, an account
//   token with the `account:sandboxes:write` scope, takes precedence over TUIST_TOKEN for these
//   tools only.
// - The account comes from tuist.toml's `project`, the start tool's `account` input,
//   TUIST_MAC_ACCOUNT or TUIST_OIDC_ACCOUNT. On Linux the CLI cannot read Tuist.swift.
// - TUIST_MAC_CLI runs another CLI binary, such as a preview build.
//
// Customers copy this file from main into their own plugins, and the docs link it. Keep it one
// self-contained file so it installs from one URL (a single-file plugin registers its skill from
// the cache directory, hence the inline SKILL.md), keep the sync and streaming logic in the CLI,
// and keep it working with the oldest CLI the docs name.

import type { PluginAPI, PluginToolResult } from '@ampcode/plugin'
import { spawn } from 'node:child_process'
import { mkdir, mkdtemp, readFile, rm, writeFile } from 'node:fs/promises'
import { tmpdir } from 'node:os'
import { basename, join } from 'node:path'

export const description =
	'A macOS Tuist sandbox per thread for Xcode builds, tests and the iOS Simulator: mirrors the worktree to the Mac before each command, streams output and returns simulator screenshots. Uses the Tuist CLI.'

const DOCS = 'https://tuist.dev/en/docs/guides/features/sandboxes/amp#remote-mac'
const CLI = process.env.TUIST_MAC_CLI ?? 'tuist'
const PATH_PREFIX = 'export PATH="/opt/homebrew/bin:/usr/local/bin:$HOME/.local/bin:$PATH" PAGER=cat GIT_PAGER=cat\n'
const MAX_OUTPUT = 30_000

const SKILL = `---
name: remote-mac
description: Builds, tests and runs Apple-platform code (Xcode, xcodebuild, Swift for iOS or macOS, the iOS Simulator) on a Tuist macOS sandbox from a Linux orb or any machine that is not a Mac. Use when a task needs xcodebuild, simulators, simulator screenshots, a built .app or .xcresult, or other macOS-only tools and \`uname\` is not Darwin.
builtin-tools:
  - tuist_mac_start
  - tuist_mac_shell
  - tuist_mac_download
  - tuist_mac_screenshot
  - tuist_mac_stop
---

# Remote Mac

These tools give this thread a Tuist macOS sandbox: a Mac with Xcode, iOS simulators and Homebrew. Keep editing files here; \`tuist_mac_shell\` mirrors the Git worktree onto the Mac before each command, including unpushed commits and uncommitted or untracked (non-ignored) changes.

## Workflow

1. \`tuist_mac_start\` once per thread. It creates the Mac (or reuses the thread's), mirrors the worktree and reports the macOS and Xcode versions.
2. \`tuist_mac_shell\` for every command. It runs bash in the repository root on the Mac (or \`cwd\`, relative to it) and streams output however long the command takes. Sync is one way: never edit tracked files on the Mac, because the next sync overwrites them. Ignored files the Mac creates, such as \`DerivedData\`, survive, so builds stay incremental.
3. \`tuist_mac_screenshot\` returns the booted simulator (or \`target: "screen"\`) as an image.
4. \`tuist_mac_download\` copies a file or directory, such as a built \`.app\` or an \`.xcresult\`, back here.
5. \`tuist_mac_stop\` when the task is done, so the Mac does not hold capacity. Tuist pauses an idle Mac and the next command resumes it, so stop only when the work is finished.

## Simulator tips

- Boot before installing: \`xcrun simctl boot "iPhone 17 Pro" || true\`. List devices with \`xcrun simctl list devices available\`.
- Build into a known directory: \`xcodebuild ... -derivedDataPath build/dd CODE_SIGNING_ALLOWED=NO build\`, then \`xcrun simctl install booted build/dd/Build/Products/Debug-iphonesimulator/<App>.app\` and \`xcrun simctl launch booted <bundle id>\`.
- Pipe long build output through \`tail\` or \`xcbeautify\` to keep results short.

## Setup problems

The tools' errors say what is missing. Setup is described at ${DOCS}.

- **Account**: when the repository has no \`tuist.toml\` with \`project = "<account>/<project>"\`, call \`tuist_mac_start\` with \`account\`: the account part of \`fullHandle\` in \`Tuist.swift\`, or ask the user for their Tuist account handle.
- **CLI missing or too old**: install the latest Tuist CLI, for example \`mise use -g tuist@latest\`, and tell the user to add it to the environment's setup script.
- **Authentication**: in an Amp orb, a workspace admin connects the Amp workspace to the Tuist account (Tuist dashboard, Settings, Integrations, Amp). Elsewhere, \`tuist auth login\`, or a \`TUIST_MAC_TOKEN\` secret with an account token that has the \`account:sandboxes:write\` scope. Ask the user; don't work around it.
`

interface SessionRecord {
	sandboxId: string
	account?: string
	// The repository's path on the Mac, from the last sync.
	root?: string
}

interface Sandbox {
	id: string
	state: string
	status?: string
	node_name?: string | null
}

export default async function (amp: PluginAPI) {
	// The tools stay out of unrelated threads until the agent loads this skill (`builtin-tools`).
	// A single-file plugin registers skills from its cache directory.
	const skillDirectory = join(amp.system.cacheDirectory, 'skills', 'remote-mac')
	await mkdir(skillDirectory, { recursive: true })
	await writeFile(join(skillDirectory, 'SKILL.md'), SKILL)
	await amp.registerSkill({ path: skillDirectory })

	const sessions = new Map<string, SessionRecord>()
	const stateFile = join(amp.system.cacheDirectory, 'sessions.json')
	const root = amp.system.workspaceRoot ? amp.helpers.filePathFromURI(amp.system.workspaceRoot) : null

	const loaded = readFile(stateFile, 'utf8')
		.then((text) => {
			for (const [thread, record] of Object.entries(JSON.parse(text) as Record<string, SessionRecord>)) sessions.set(thread, record)
		})
		.catch(() => {})

	async function persist() {
		await writeFile(stateFile, JSON.stringify(Object.fromEntries(sessions), null, 2))
	}

	async function withKeepAlive<T>(fn: () => Promise<T>): Promise<T> {
		const lease = await amp.system.executor.keepAlive().catch(() => null)
		try {
			return await fn()
		} finally {
			lease?.unsubscribe()
		}
	}

	function requireRoot(): string {
		if (!root) throw new Error('Amp is running without a workspace.')
		return root
	}

	async function recordFor(thread: string): Promise<SessionRecord> {
		await loaded
		const record = sessions.get(thread)
		if (!record) throw new Error('No Mac in this thread. Call tuist_mac_start first.')
		return record
	}

	// Runs `tuist sandbox <subcommand>` for the thread's sandbox.
	function run(record: SessionRecord, args: string[], signal?: AbortSignal) {
		return sandbox(args, { cwd: requireRoot(), account: record.account, signal })
	}

	// Mirrors the worktree into the Mac and remembers where the repository is there.
	async function sync(record: SessionRecord, signal?: AbortSignal): Promise<string> {
		const result = await sandboxJSON<{ root: string; changed_files: number; bytes: number; uploaded: boolean }>(
			['sync', record.sandboxId],
			{ cwd: requireRoot(), account: record.account, signal },
		)
		if (record.root !== result.root) {
			record.root = result.root
			await persist()
		}
		if (!result.uploaded) return 'nothing, already on the Mac'
		const size = result.bytes < 1024 * 1024 ? `${Math.ceil(result.bytes / 1024)} KB` : `${(result.bytes / 1024 / 1024).toFixed(1)} MB`
		return `${result.changed_files} changed file${result.changed_files === 1 ? '' : 's'} (${size})`
	}

	amp.registerTool({
		name: 'tuist_mac_start',
		title: 'Start Mac',
		transcriptGroup: { active: 'Starting a Tuist Mac', complete: 'Started a Tuist Mac' },
		description:
			"Start a macOS Tuist sandbox (Xcode, simulators, Homebrew) for this thread, or reuse the thread's existing one. " +
			'Use it when the task needs macOS: Xcode builds, Apple-platform tests, or the iOS Simulator. ' +
			'It mirrors the worktree onto the Mac, including unpushed commits, uncommitted and untracked (non-ignored) changes, and tuist_mac_shell mirrors it again before each command. ' +
			'Tuist pauses an idle Mac and resumes it on the next command; tuist_mac_stop deletes it.',
		inputSchema: {
			type: 'object',
			properties: {
				account: {
					type: 'string',
					description:
						'Tuist account handle that owns the Mac. Needed when the repository has no tuist.toml with `project = "<account>/<project>"`, for example one configured with Tuist.swift: use the account part of its `fullHandle`.',
				},
				memory_gb: { type: 'number', enum: [8, 16, 24], description: 'Memory with 8 vCPUs. Default 16.' },
				workspace_gb: { type: 'number', description: 'Workspace disk, 1-100 GB. Default 30.' },
			},
		},
		async execute(input, ctx) {
			await loaded
			const thread = ctx.thread.id
			const cwd = requireRoot()
			const existing = sessions.get(thread)
			if (existing) {
				const shown = await run(existing, ['show', existing.sandboxId, '--json'])
				const state = shown.exitCode === 0 ? (JSON.parse(shown.stdout) as Sandbox) : null
				if (state && !['error', 'deleted', 'archived'].includes(state.state)) {
					return `The thread's Mac (sandbox ${state.id}) is ${state.status ?? state.state}; tuist_mac_shell resumes it if paused.`
				}
				sessions.delete(thread)
				await persist()
			}
			const account = typeof input.account === 'string' && input.account.trim() ? input.account.trim() : defaultAccount()
			const memoryGB = input.memory_gb === 8 || input.memory_gb === 24 ? input.memory_gb : 16
			const workspaceGB = typeof input.workspace_gb === 'number' ? Math.min(100, Math.max(1, Math.round(input.workspace_gb))) : 30
			return withKeepAlive(async () => {
				const started = Date.now()
				const created = await sandboxJSON<Sandbox>(
					['create', '--platform', 'macos', '--vcpus', '8', '--memory-gb', String(memoryGB), '--workspace-gb', String(workspaceGB)],
					{ cwd, account, signal: ctx.signal },
				)
				const record: SessionRecord = { sandboxId: created.id, account }
				sessions.set(thread, record)
				await persist()
				try {
					const booted = Date.now()
					const synced = await sync(record, ctx.signal)
					const info = await run(record, ['exec', record.sandboxId, '--', `${PATH_PREFIX}sw_vers -productVersion; xcodebuild -version | head -1`], ctx.signal)
					return (
						`Mac ready (sandbox ${created.id} on ${created.node_name ?? 'a Tuist host'}): booted in ${Math.round((booted - started) / 1000)}s, ` +
						`synced ${synced} in ${Math.round((Date.now() - booted) / 1000)}s.\n${info.stdout.trim()}\nRepository: ${record.root}`
					)
				} catch (error) {
					await stop(thread).catch(() => {})
					throw error
				}
			})
		},
	})

	amp.registerTool({
		name: 'tuist_mac_shell',
		title: 'Run on Mac',
		transcriptGroup: { active: 'Running on the Mac', complete: 'Ran on the Mac' },
		description:
			"Run a bash command on this thread's Tuist Mac, in the mirrored repository. First mirrors the worktree onto the Mac, one way: " +
			'edit files here, not on the Mac, because the next mirror overwrites Mac-side changes to files the repository tracks. Files the Mac created that Git ignores, such as build products, stay. ' +
			'Output streams however long the command runs. Returns the exit code and combined output (long output keeps its start and end).',
		inputSchema: {
			type: 'object',
			properties: {
				command: { type: 'string', description: 'bash command, such as `xcodebuild -scheme App -destination "platform=iOS Simulator,name=iPhone 17 Pro" build`.' },
				cwd: { type: 'string', description: 'Directory relative to the repository root. Default: the root.' },
				sync: { type: 'boolean', description: 'Mirror the worktree first. Default true.' },
				timeout_seconds: { type: 'number', description: 'Default 1800.' },
			},
			required: ['command'],
		},
		async execute(input, ctx) {
			const record = await recordFor(ctx.thread.id)
			const timeout = Math.min(21_600, Math.max(1, Math.round(typeof input.timeout_seconds === 'number' ? input.timeout_seconds : 1800)))
			return withKeepAlive(async () => {
				const synced = input.sync === false && record.root ? 'not synced' : await sync(record, ctx.signal)
				const dir = typeof input.cwd === 'string' && input.cwd ? `${record.root}/${input.cwd}` : record.root!
				const started = Date.now()
				const result = await run(
					record,
					['exec', record.sandboxId, '--cwd', dir, '--timeout', String(timeout), '--', `${PATH_PREFIX}${String(input.command)}`],
					ctx.signal,
				)
				const seconds = ((Date.now() - started) / 1000).toFixed(1)
				return `exit code ${result.exitCode} after ${seconds}s (${synced})\n${truncate(result.output)}`
			})
		},
	})

	amp.registerTool({
		name: 'tuist_mac_download',
		title: 'Download from Mac',
		transcriptGroup: { active: 'Downloading from the Mac', complete: 'Downloaded from the Mac' },
		description:
			"Copy a file or directory from this thread's Tuist Mac to this machine, such as a built .app, an .xcresult bundle or logs. Returns the local path.",
		inputSchema: {
			type: 'object',
			properties: {
				path: { type: 'string', description: 'Path on the Mac, absolute or relative to the repository root.' },
				output: { type: 'string', description: 'Local directory to copy it into. Default: a directory under the system temporary directory.' },
			},
			required: ['path'],
		},
		async execute(input, ctx) {
			const record = await recordFor(ctx.thread.id)
			const remote = String(input.path).startsWith('/') ? String(input.path) : `${record.root}/${input.path}`
			const output = typeof input.output === 'string' && input.output ? input.output : join(tmpdir(), 'tuist-mac', ctx.thread.id)
			await mkdir(output, { recursive: true })
			const result = await run(record, ['cp', `${record.sandboxId}:${remote}`, `${output}/`], ctx.signal)
			if (result.exitCode !== 0) throw new Error(`Download failed:\n${truncate(result.output)}`)
			return `Downloaded to ${join(output, basename(remote))}`
		},
	})

	amp.registerTool({
		name: 'tuist_mac_screenshot',
		title: 'Mac screenshot',
		transcriptGroup: { active: 'Capturing the Mac', complete: 'Captured the Mac' },
		description: "Capture the booted iOS Simulator (default) or the whole screen of this thread's Tuist Mac and return it as an image.",
		inputSchema: {
			type: 'object',
			properties: {
				target: { type: 'string', enum: ['simulator', 'screen'], description: 'Default simulator.' },
			},
		},
		async execute(input, ctx): Promise<PluginToolResult> {
			const record = await recordFor(ctx.thread.id)
			const shot = `/tmp/tuist-mac-screenshot-${Date.now()}.jpg`
			const capture =
				input.target === 'screen' ? 'screencapture -x "$png" 2>/dev/null' : 'xcrun simctl io booted screenshot --type=png "$png" >/dev/null 2>&1'
			const taken = await run(
				record,
				[
					'exec',
					record.sandboxId,
					'--timeout',
					'120',
					'--',
					`set -euo pipefail\n${PATH_PREFIX}png=$(mktemp /tmp/tm.XXXXXX)\n${capture}\nsips -Z 1600 -s format jpeg -s formatOptions 75 "$png" --out ${shot} >/dev/null 2>&1\nrm -f "$png"`,
				],
				ctx.signal,
			)
			if (taken.exitCode !== 0) throw new Error(`Screenshot failed:\n${truncate(taken.output)}`)
			const local = await mkdtemp(join(tmpdir(), 'tuist-mac-shot-'))
			try {
				const downloaded = await run(record, ['cp', `${record.sandboxId}:${shot}`, `${local}/`], ctx.signal)
				if (downloaded.exitCode !== 0) throw new Error(`Copying the screenshot failed:\n${truncate(downloaded.output)}`)
				void run(record, ['exec', record.sandboxId, '--', `rm -f ${shot}`]).catch(() => {})
				const data = await readFile(join(local, basename(shot)))
				try {
					const { url } = await amp.attachments.upload({ data, mimeType: 'image/jpeg' })
					return [{ type: 'image', mimeType: 'image/jpeg', url }]
				} catch {
					return [{ type: 'image', mimeType: 'image/jpeg', data: data.toString('base64') }]
				}
			} finally {
				await rm(local, { recursive: true, force: true })
			}
		},
	})

	amp.registerTool({
		name: 'tuist_mac_stop',
		title: 'Stop Mac',
		description: "Delete this thread's Tuist Mac and everything on it.",
		inputSchema: { type: 'object', properties: {} },
		async execute(_input, ctx) {
			await recordFor(ctx.thread.id)
			await stop(ctx.thread.id)
			return 'Mac deleted.'
		},
	})

	async function stop(thread: string) {
		const record = sessions.get(thread)
		if (!record) return
		sessions.delete(thread)
		await persist()
		const result = await run(record, ['delete', record.sandboxId, '--yes'])
		if (result.exitCode !== 0) throw new Error(`Deleting the Mac failed:\n${truncate(result.output)}`)
	}
}

function defaultAccount(): string | undefined {
	return process.env.TUIST_MAC_ACCOUNT || process.env.TUIST_OIDC_ACCOUNT || undefined
}

interface CLIResult {
	exitCode: number
	// stdout and stderr interleaved, as a terminal shows them.
	output: string
	stdout: string
}

interface CLIOptions {
	cwd: string
	account?: string
	signal?: AbortSignal
}

// TUIST_MAC_TOKEN replaces TUIST_TOKEN for these tools, for orbs whose TUIST_TOKEN is a project
// token without the sandbox scope.
function environment(): NodeJS.ProcessEnv {
	return process.env.TUIST_MAC_TOKEN ? { ...process.env, TUIST_TOKEN: process.env.TUIST_MAC_TOKEN } : process.env
}

let cliChecked: Promise<void> | null = null

// Fails with what to install when the CLI is missing or predates `tuist sandbox sync`. A failed
// check runs again on the next call, so installing the CLI mid-thread works.
function checkCLI(cwd: string): Promise<void> {
	if (!cliChecked) {
		cliChecked = runCLI(['sandbox', '--help'], { cwd }).then(
			(help) => {
				if (!/^\s+sync\s/m.test(help.output)) {
					throw new Error(`This Tuist CLI (${CLI}) has no \`tuist sandbox sync\`. Install the latest Tuist release; see ${DOCS}.`)
				}
			},
			(error: NodeJS.ErrnoException) => {
				throw error.code === 'ENOENT' ? new Error(`The Tuist CLI (${CLI}) is not installed. Install the latest Tuist release; see ${DOCS}.`) : error
			},
		)
		cliChecked.catch(() => {
			cliChecked = null
		})
	}
	return cliChecked
}

// Runs `tuist sandbox <args>` and returns its exit code and combined output. An abort sends SIGINT,
// which makes `tuist sandbox exec` cancel the command in the sandbox before it exits.
async function sandbox(args: string[], { cwd, account, signal }: CLIOptions): Promise<CLIResult> {
	await checkCLI(cwd)
	const [subcommand, ...rest] = args
	const separator = rest.indexOf('--')
	const options = separator < 0 ? rest : rest.slice(0, separator)
	const trailing = separator < 0 ? [] : rest.slice(separator)
	return runCLI(['sandbox', subcommand, ...options, ...(account ? ['--account', account] : []), ...trailing], { cwd, signal })
}

function runCLI(args: string[], { cwd, signal }: { cwd: string; signal?: AbortSignal }): Promise<CLIResult> {
	return new Promise((resolve, reject) => {
		const child = spawn(CLI, args, { cwd, env: environment(), stdio: ['ignore', 'pipe', 'pipe'] })
		const output = new HeadTail()
		const stdout = new HeadTail()
		child.stdout.on('data', (chunk: Buffer) => {
			output.push(chunk.toString())
			stdout.push(chunk.toString())
		})
		child.stderr.on('data', (chunk: Buffer) => output.push(chunk.toString()))
		const onAbort = () => child.kill('SIGINT')
		signal?.addEventListener('abort', onAbort, { once: true })
		child.on('error', (error) => {
			signal?.removeEventListener('abort', onAbort)
			reject(error)
		})
		child.on('close', (code, killSignal) => {
			signal?.removeEventListener('abort', onAbort)
			resolve({ exitCode: code ?? (killSignal === 'SIGINT' ? 130 : 1), output: output.text(), stdout: stdout.text() })
		})
	})
}

// Runs a CLI step that must succeed and returns its parsed `--json` output.
async function sandboxJSON<T>(args: string[], options: CLIOptions): Promise<T> {
	const result = await sandbox([...args, '--json'], options)
	if (result.exitCode !== 0) throw new Error(`tuist sandbox ${args[0]} failed:\n${result.output.slice(-4000)}${hint(result.output)}`)
	return JSON.parse(result.stdout) as T
}

function hint(output: string): string {
	if (output.includes('Pass --account')) {
		return '\nCall tuist_mac_start with `account`: the account part of `fullHandle` in Tuist.swift, or the Tuist account handle the user gives you.'
	}
	if (/need to be authenticated|not authorized|auth login/i.test(output)) {
		return (
			'\nThe Tuist CLI cannot use this account\'s sandboxes. In an Amp orb, a workspace admin connects the Amp workspace to the Tuist account; ' +
			`elsewhere, run \`tuist auth login\` or set TUIST_MAC_TOKEN to an account token with the account:sandboxes:write scope. See ${DOCS}.`
		)
	}
	return ''
}

function truncate(text: string): string {
	if (text.length <= MAX_OUTPUT) return text
	const head = text.slice(0, 5_000)
	const tail = text.slice(-(MAX_OUTPUT - 5_000))
	return `${head}\n… ${text.length - MAX_OUTPUT} characters omitted …\n${tail}`
}

// Keeps the first 20,000 and the last 200,000 characters of a stream.
class HeadTail {
	private head = ''
	private tail = ''
	private dropped = 0

	push(data: string) {
		if (this.head.length < 20_000) {
			const room = 20_000 - this.head.length
			this.head += data.slice(0, room)
			data = data.slice(room)
		}
		this.tail += data
		if (this.tail.length > 200_000) {
			this.dropped += this.tail.length - 200_000
			this.tail = this.tail.slice(-200_000)
		}
	}

	text(): string {
		return this.dropped ? `${this.head}\n… ${this.dropped} characters omitted …\n${this.tail}` : this.head + this.tail
	}
}
