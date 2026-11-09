import type { PluginAPI, PluginToolResult } from '@ampcode/plugin'
import { mkdir, mkdtemp, readFile, rm, writeFile } from 'node:fs/promises'
import { tmpdir } from 'node:os'
import { basename, join } from 'node:path'
import { sandbox, sandboxJSON } from './lib/tuist.ts'

export const description =
	'A macOS Tuist sandbox per thread for Xcode builds, tests and the iOS Simulator: mirrors the worktree to the Mac before each command, streams output and returns simulator screenshots. Uses the Tuist CLI.'

const PATH_PREFIX = 'export PATH="/opt/homebrew/bin:/usr/local/bin:$HOME/.local/bin:$PATH" PAGER=cat GIT_PAGER=cat\n'
const MAX_OUTPUT = 30_000

interface SessionRecord {
	sandboxId: string
	// The repository's path on the Mac, from the last sync.
	root?: string
}

interface Sandbox {
	id: string
	state: string
	status?: string
	node_name?: string | null
	error_message?: string | null
}

export default function (amp: PluginAPI) {
	const sessions = new Map<string, SessionRecord>()
	const stateFile = join(amp.system.cacheDirectory, 'sessions.json')
	const root = amp.system.workspaceRoot ? amp.helpers.filePathFromURI(amp.system.workspaceRoot) : null

	const loaded = readFile(stateFile, 'utf8')
		.then((text) => {
			for (const [thread, record] of Object.entries(JSON.parse(text) as Record<string, SessionRecord>)) sessions.set(thread, record)
		})
		.catch(() => {})

	async function persist() {
		await mkdir(amp.system.cacheDirectory, { recursive: true })
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

	// Mirrors the worktree into the Mac and remembers where the repository is there.
	async function sync(record: SessionRecord, signal?: AbortSignal): Promise<string> {
		const result = await sandboxJSON<{ root: string; base: string; patch_bytes: number; uploaded: boolean }>(
			['sync', record.sandboxId],
			{ cwd: requireRoot(), signal },
		)
		if (record.root !== result.root) {
			record.root = result.root
			await persist()
		}
		const size = result.patch_bytes < 1024 ? `${result.patch_bytes} B` : `${Math.round(result.patch_bytes / 1024)} KB`
		return `${size} of changes against ${result.base.slice(0, 12)}${result.uploaded ? '' : ', already on the Mac'}`
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
				const shown = await sandbox(['show', existing.sandboxId, '--json'], { cwd })
				const state = shown.exitCode === 0 ? (JSON.parse(shown.stdout) as Sandbox) : null
				if (state && !['error', 'deleted', 'archived'].includes(state.state)) {
					return `The thread's Mac (sandbox ${state.id}) is ${state.status ?? state.state}; tuist_mac_shell resumes it if paused.`
				}
				sessions.delete(thread)
				await persist()
			}
			const memoryGB = input.memory_gb === 8 || input.memory_gb === 24 ? input.memory_gb : 16
			const workspaceGB = typeof input.workspace_gb === 'number' ? Math.min(100, Math.max(1, Math.round(input.workspace_gb))) : 30
			return withKeepAlive(async () => {
				const started = Date.now()
				const created = await sandboxJSON<Sandbox>(
					['create', '--platform', 'macos', '--vcpus', '8', '--memory-gb', String(memoryGB), '--workspace-gb', String(workspaceGB)],
					{ cwd, signal: ctx.signal },
				)
				const record: SessionRecord = { sandboxId: created.id }
				sessions.set(thread, record)
				await persist()
				try {
					const booted = Date.now()
					const synced = await sync(record, ctx.signal)
					const info = await sandbox(['exec', record.sandboxId, '--', `${PATH_PREFIX}sw_vers -productVersion; xcodebuild -version | head -1`], {
						cwd,
						signal: ctx.signal,
					})
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
				const result = await sandbox(
					['exec', record.sandboxId, '--cwd', dir, '--timeout', String(timeout), '--', `${PATH_PREFIX}${String(input.command)}`],
					{ cwd: requireRoot(), signal: ctx.signal },
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
			const result = await sandbox(['cp', `${record.sandboxId}:${remote}`, `${output}/`], { cwd: requireRoot(), signal: ctx.signal })
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
			const cwd = requireRoot()
			const shot = `/tmp/tuist-mac-screenshot-${Date.now()}.jpg`
			const capture =
				input.target === 'screen' ? 'screencapture -x "$png" 2>/dev/null' : 'xcrun simctl io booted screenshot --type=png "$png" >/dev/null 2>&1'
			const taken = await sandbox(
				[
					'exec',
					record.sandboxId,
					'--timeout',
					'120',
					'--',
					`set -euo pipefail\n${PATH_PREFIX}png=$(mktemp /tmp/tm.XXXXXX)\n${capture}\nsips -Z 1600 -s format jpeg -s formatOptions 75 "$png" --out ${shot} >/dev/null 2>&1\nrm -f "$png"`,
				],
				{ cwd, signal: ctx.signal },
			)
			if (taken.exitCode !== 0) throw new Error(`Screenshot failed:\n${truncate(taken.output)}`)
			const local = await mkdtemp(join(tmpdir(), 'tuist-mac-shot-'))
			try {
				const downloaded = await sandbox(['cp', `${record.sandboxId}:${shot}`, `${local}/`], { cwd, signal: ctx.signal })
				if (downloaded.exitCode !== 0) throw new Error(`Copying the screenshot failed:\n${truncate(downloaded.output)}`)
				void sandbox(['exec', record.sandboxId, '--', `rm -f ${shot}`], { cwd }).catch(() => {})
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
		const result = await sandbox(['delete', record.sandboxId, '--yes'], { cwd: requireRoot() })
		if (result.exitCode !== 0) throw new Error(`Deleting the Mac failed:\n${truncate(result.output)}`)
	}
}

function truncate(text: string): string {
	if (text.length <= MAX_OUTPUT) return text
	const head = text.slice(0, 5_000)
	const tail = text.slice(-(MAX_OUTPUT - 5_000))
	return `${head}\n… ${text.length - MAX_OUTPUT} characters omitted …\n${tail}`
}
