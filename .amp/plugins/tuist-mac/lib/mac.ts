import { ApiError, type LogLine, type SandboxClient } from './sandbox.ts'

// Long commands go through the sandbox commands API: the server starts the
// command detached in the guest and streams its output as ND-JSON, so a build
// outlives any one HTTP request. Short steps use a single foreground exec.
//
// Kept under macOS's ARG_MAX (1 MiB for argv and environment), since the
// guest runs every exec as `/bin/bash -lc <command>`.
const CHUNK = 256 * 1024
// A long log keeps its start and end.
const LOG_HEAD = 20_000
const LOG_TAIL = 200_000
// How long a command waits for its host while CI holds it, and how long a
// running command's log stream keeps reconnecting without progress.
const HOST_WAIT_MS = 15 * 60_000

export interface RunResult {
	exitCode: number
	output: string
}

export class Mac {
	constructor(
		private readonly client: SandboxClient,
		readonly sandboxId: string,
	) {}

	// One foreground exec, for short steps that cannot outlive a request.
	async exec(command: string, timeoutMs = 60_000, signal?: AbortSignal): Promise<RunResult> {
		const result = await waitForHost(() => this.client.exec(this.sandboxId, command, timeoutMs, signal), signal)
		return { exitCode: result.exit_code ?? 124, output: result.stdout + result.stderr }
	}

	// Runs `script` with bash in `cwd` until it ends or `timeoutMs` passes,
	// however long that is, and returns its combined output.
	async run(script: string, { cwd, timeoutMs, signal }: { cwd: string; timeoutMs: number; signal?: AbortSignal }): Promise<RunResult> {
		const command = await waitForHost(() => this.client.startCommand(this.sandboxId, { command: script, cwd, timeout_ms: timeoutMs }), signal)
		const output = new HeadTail()
		const offsets = { stdout: 0, stderr: 0 }
		const onAbort = () => void this.client.cancelCommand(this.sandboxId, command.id).catch(() => {})
		signal?.addEventListener('abort', onAbort, { once: true })
		try {
			// Failed reconnects in a row, and since when; reset by any progress.
			let failures = 0
			let failingSince = 0
			for (;;) {
				signal?.throwIfAborted()
				let end: LogLine | undefined
				let failure: unknown
				try {
					for await (const line of this.client.logs(this.sandboxId, command.id, offsets, signal)) {
						if (line.type === 'stdout' || line.type === 'stderr') {
							output.push(line.data)
							offsets[line.type] = line.offset
							failures = 0
						} else {
							end = line
						}
					}
				} catch (error) {
					if (signal?.aborted || (error instanceof ApiError && error.status < 500)) throw error
					failure = error
				}
				if (end?.type === 'exit') {
					if (end.status === 'timed_out') output.push(`\nMac command timed out after ${Math.round(timeoutMs / 1000)}s\n`)
					if (end.status === 'lost') output.push('\nThe Mac command was lost (the Mac restarted or was paused).\n')
					return { exitCode: end.exit_code ?? 124, output: output.text() }
				}
				// The server ends a long stream without an exit line; resume it.
				if (!failure && !end) {
					failures = 0
					continue
				}
				// A dropped stream, a 5xx, or an `error` line mid-stream, which the
				// server sends when a read fails, such as while CI holds the host.
				// The command keeps running; reconnect, and the first read answers
				// with a plain status (404 for a gone command ends the loop above).
				if (failures++ === 0) failingSince = Date.now()
				if (Date.now() - failingSince > HOST_WAIT_MS) {
					throw failure ?? new Error(`Lost track of the Mac command: ${end?.type === 'error' ? end.message : 'no output'}`)
				}
				await new Promise((r) => setTimeout(r, Math.min(30_000, 1000 * 2 ** failures)))
			}
		} finally {
			signal?.removeEventListener('abort', onAbort)
		}
	}

	// Writes `data` to `path` on the Mac, in pieces that fit one exec each.
	async upload(path: string, data: Buffer): Promise<void> {
		const encoded = data.toString('base64')
		const parts = Math.max(1, Math.ceil(encoded.length / CHUNK))
		for (let i = 0; i < parts; i++) {
			const chunk = encoded.slice(i * CHUNK, (i + 1) * CHUNK)
			const redirect = i === 0 ? '>' : '>>'
			const finish = i === parts - 1 ? `\nbase64 --decode < ${path}.b64 > ${path} && rm -f ${path}.b64` : ''
			const result = await this.exec(`set -e; mkdir -p "$(dirname ${path})"; printf %s '${chunk}' ${redirect} ${path}.b64${finish}`, 120_000)
			if (result.exitCode !== 0) throw new Error(`Uploading to the Mac failed:\n${result.output.slice(0, 2000)}`)
		}
	}
}

// Tuist Macs share hosts with CI, which comes first: while CI holds the
// host, the server refuses new work on the Mac with 503. Wait for the host
// instead of failing the call.
async function waitForHost<T>(call: () => Promise<T>, signal?: AbortSignal): Promise<T> {
	const deadline = Date.now() + HOST_WAIT_MS
	for (let attempt = 0; ; attempt++) {
		try {
			return await call()
		} catch (error) {
			if (!(error instanceof ApiError && error.status === 503) || Date.now() >= deadline) throw error
			signal?.throwIfAborted()
			await new Promise((r) => setTimeout(r, Math.min(30_000, 2000 * 2 ** attempt)))
		}
	}
}

// Keeps the first LOG_HEAD and the last LOG_TAIL characters of a stream.
class HeadTail {
	private head = ''
	private tail = ''
	private dropped = 0

	push(data: string) {
		if (this.head.length < LOG_HEAD) {
			const room = LOG_HEAD - this.head.length
			this.head += data.slice(0, room)
			data = data.slice(room)
		}
		this.tail += data
		if (this.tail.length > LOG_TAIL) {
			this.dropped += this.tail.length - LOG_TAIL
			this.tail = this.tail.slice(-LOG_TAIL)
		}
	}

	text(): string {
		return this.dropped ? `${this.head}\n… ${this.dropped} characters omitted …\n${this.tail}` : this.head + this.tail
	}
}

export function quote(value: string): string {
	return `'${value.replace(/'/g, `'\\''`)}'`
}
