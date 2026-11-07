import type { PluginAPI, PluginToolResult } from '@ampcode/plugin'
import { createHash } from 'node:crypto'
import { mkdir, readFile, writeFile } from 'node:fs/promises'
import { join } from 'node:path'
import { baseCommit, checkoutScript, originURL, syncScript, worktreePatch } from './lib/git.ts'
import { Mac, quote } from './lib/mac.ts'
import { accountHandle, SandboxClient, tuistToken } from './lib/sandbox.ts'

export const description =
	'Prototype: a macOS Tuist sandbox per thread. Mirrors the worktree to the Mac before each command, runs commands there, and returns simulator screenshots.'

const SERVER_URL = (process.env.TUIST_MAC_SERVER_URL ?? process.env.TUIST_URL ?? 'https://tuist.dev').replace(/\/$/, '')
const PATH_PREFIX = 'export PATH="/opt/homebrew/bin:/usr/local/bin:$HOME/.local/bin:$PATH" PAGER=cat GIT_PAGER=cat\n'
const MAX_OUTPUT = 30_000
const WORK = '/Users/runner/work'

interface SessionRecord {
	sandboxId: string
	account: string
	base: string
	repo: string
	lastPatchHash?: string
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

	async function client(account: string): Promise<SandboxClient> {
		return new SandboxClient(SERVER_URL, account, await tuistToken(SERVER_URL, requireRoot()))
	}

	async function macFor(thread: string): Promise<{ record: SessionRecord; mac: Mac }> {
		await loaded
		const record = sessions.get(thread)
		if (!record) throw new Error('No Mac in this thread. Call tuist_mac_start first.')
		return { record, mac: new Mac(await client(record.account), record.sandboxId) }
	}

	async function sync(record: SessionRecord, mac: Mac): Promise<string> {
		const patch = await worktreePatch(requireRoot(), record.base)
		const hash = createHash('sha256').update(patch).digest('hex').slice(0, 16)
		const remote = `/tmp/tuist-mac/patch-${hash}`
		if (record.lastPatchHash !== hash) await mac.upload(remote, patch)
		let result = await mac.exec(`cd ${record.repo}\n${syncScript(record.base, remote)}`, 300_000)
		if (result.exitCode !== 0 && record.lastPatchHash === hash) {
			// The Mac lost the patch (a fresh VM after an eviction); send it again.
			await mac.upload(remote, patch)
			result = await mac.exec(`cd ${record.repo}\n${syncScript(record.base, remote)}`, 300_000)
		}
		if (result.exitCode !== 0) throw new Error(`Syncing the worktree to the Mac failed:\n${truncate(result.output)}`)
		record.lastPatchHash = hash
		await persist()
		return `${patch.length} bytes of changes against ${record.base.slice(0, 12)}`
	}

	amp.registerTool({
		name: 'tuist_mac_start',
		title: 'Start Mac',
		transcriptGroup: { active: 'Starting a Tuist Mac', complete: 'Started a Tuist Mac' },
		description:
			"Start a macOS Tuist sandbox (Xcode, simulators, Homebrew) for this thread, or reuse the thread's existing one. " +
			'Use it when the task needs macOS: Xcode builds, Apple-platform tests, or the iOS Simulator. The Mac starts from the newest commit the remote has; ' +
			'tuist_mac_shell then mirrors local commits, uncommitted and untracked (non-ignored) changes before each command. ' +
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
			const workspace = requireRoot()
			const existing = sessions.get(thread)
			if (existing) {
				const sandbox = await (await client(existing.account)).show(existing.sandboxId).catch(() => null)
				if (sandbox && !['error', 'deleted', 'archived'].includes(sandbox.state)) {
					return `The thread's Mac (sandbox ${sandbox.id}) is ${sandbox.status ?? sandbox.state}; tuist_mac_shell resumes it if paused.`
				}
				sessions.delete(thread)
				await persist()
			}
			const memoryGB = input.memory_gb === 8 || input.memory_gb === 24 ? input.memory_gb : 16
			const workspaceGB = typeof input.workspace_gb === 'number' ? Math.min(100, Math.max(1, Math.round(input.workspace_gb))) : 30
			return withKeepAlive(async () => {
				const started = Date.now()
				const account = await accountHandle(workspace)
				const api = await client(account)
				const base = await baseCommit(workspace)
				const url = await originURL(workspace)
				const repo = `${WORK}/${url.replace(/\.git$/, '').split('/').pop() || 'repo'}`
				const sandbox = await api.create({ platform: 'darwin', vcpus: 8, memory_mb: memoryGB * 1024, workspace_gb: workspaceGB })
				const record: SessionRecord = { sandboxId: sandbox.id, account, base, repo }
				sessions.set(thread, record)
				await persist()
				try {
					let state = sandbox
					while (state.state !== 'running') {
						ctx.signal?.throwIfAborted()
						if (state.state === 'error' || state.state === 'deleted') throw new Error(`The Mac failed to start: ${state.error_message ?? state.state}`)
						if (Date.now() - started > 20 * 60_000) throw new Error('Timed out waiting for the Mac to start.')
						await new Promise((r) => setTimeout(r, 3000))
						state = await api.show(sandbox.id)
					}
					const booted = Date.now()
					const mac = new Mac(api, sandbox.id)
					const checkout = await mac.run(checkoutScript(repo, quote(url), base), { cwd: WORK, timeoutMs: 30 * 60_000, signal: ctx.signal })
					if (checkout.exitCode !== 0) throw new Error(`Checking out ${base.slice(0, 12)} on the Mac failed:\n${truncate(checkout.output)}`)
					const info = await mac.exec(`${PATH_PREFIX}sw_vers -productVersion; xcodebuild -version | head -1`)
					return (
						`Mac ready (sandbox ${sandbox.id} on ${state.node_name ?? 'a Tuist host'}): booted in ${Math.round((booted - started) / 1000)}s, ` +
						`checked out ${base.slice(0, 12)} in ${Math.round((Date.now() - booted) / 1000)}s.\n${info.output.trim()}\nRepository: ${repo}`
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
			'edit files here, not on the Mac, because the next mirror overwrites Mac-side changes to files the repository tracks and removes untracked files the Mac created unless Git ignores them. ' +
			'Returns the exit code and combined output (long output keeps its start and end).',
		inputSchema: {
			type: 'object',
			properties: {
				command: { type: 'string', description: 'bash command, such as `xcodebuild -scheme App -destination "platform=iOS Simulator,name=iPhone 17" build`.' },
				cwd: { type: 'string', description: 'Directory relative to the repository root. Default: the root.' },
				sync: { type: 'boolean', description: 'Mirror the worktree first. Default true.' },
				timeout_seconds: { type: 'number', description: 'Default 1800.' },
			},
			required: ['command'],
		},
		async execute(input, ctx) {
			const { record, mac } = await macFor(ctx.thread.id)
			const timeoutMs = (typeof input.timeout_seconds === 'number' ? input.timeout_seconds : 1800) * 1000
			return withKeepAlive(async () => {
				const synced = input.sync === false ? 'not synced' : await sync(record, mac)
				const cwd = typeof input.cwd === 'string' && input.cwd ? `${record.repo}/${input.cwd}` : record.repo
				const started = Date.now()
				const result = await mac.run(`${PATH_PREFIX}${String(input.command)}`, { cwd, timeoutMs, signal: ctx.signal })
				const seconds = ((Date.now() - started) / 1000).toFixed(1)
				return `exit code ${result.exitCode} after ${seconds}s (${synced})\n${truncate(result.output)}`
			})
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
			const { mac } = await macFor(ctx.thread.id)
			const capture =
				input.target === 'screen' ? 'screencapture -x "$png" 2>/dev/null' : 'xcrun simctl io booted screenshot --type=png "$png" >/dev/null 2>&1'
			const result = await mac.exec(
				`set -euo pipefail\n${PATH_PREFIX}png=$(mktemp /tmp/tm.XXXXXX); jpg="$png.jpg"\n${capture}\n` +
					`sips -Z 1600 -s format jpeg -s formatOptions 75 "$png" --out "$jpg" >/dev/null 2>&1\necho __TM_IMAGE__\nbase64 < "$jpg"\nrm -f "$png" "$jpg"`,
				60_000,
				ctx.signal,
			)
			if (result.exitCode !== 0) throw new Error(`Screenshot failed:\n${truncate(result.output)}`)
			// simctl and sips print notes; the image is everything after the marker.
			const encoded = result.output.slice(result.output.lastIndexOf('__TM_IMAGE__') + '__TM_IMAGE__'.length)
			const data = Buffer.from(encoded.replace(/\s+/g, ''), 'base64')
			try {
				const { url } = await amp.attachments.upload({ data, mimeType: 'image/jpeg' })
				return [{ type: 'image', mimeType: 'image/jpeg', url }]
			} catch {
				return [{ type: 'image', mimeType: 'image/jpeg', data: data.toString('base64') }]
			}
		},
	})

	amp.registerTool({
		name: 'tuist_mac_stop',
		title: 'Stop Mac',
		description: "Delete this thread's Tuist Mac and everything on it.",
		inputSchema: { type: 'object', properties: {} },
		async execute(_input, ctx) {
			await macFor(ctx.thread.id)
			await stop(ctx.thread.id)
			return 'Mac deleted.'
		},
	})

	async function stop(thread: string) {
		const record = sessions.get(thread)
		if (!record) return
		sessions.delete(thread)
		await persist()
		await (await client(record.account)).delete(record.sandboxId)
	}
}

function truncate(text: string): string {
	if (text.length <= MAX_OUTPUT) return text
	const head = text.slice(0, 5_000)
	const tail = text.slice(-(MAX_OUTPUT - 5_000))
	return `${head}\n… ${text.length - MAX_OUTPUT} characters omitted …\n${tail}`
}
