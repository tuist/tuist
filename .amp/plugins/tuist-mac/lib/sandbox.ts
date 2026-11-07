import { readFile } from 'node:fs/promises'
import { join } from 'node:path'
import { execText } from './run.ts'

export interface Sandbox {
	id: string
	state: 'creating' | 'running' | 'resuming' | 'paused' | 'archived' | 'error' | 'deleted'
	status?: string
	platform?: string
	error_message?: string | null
	node_name?: string | null
}

export interface ExecResult {
	exit_code: number | null
	stdout: string
	stderr: string
}

// The sandboxes API (`/api/accounts/:handle/sandboxes`), which `tuist sandbox`
// also uses. Every call needs a user token of an account member.
export class SandboxClient {
	constructor(
		readonly serverURL: string,
		readonly account: string,
		private readonly token: string,
	) {}

	create(body: Record<string, unknown>): Promise<Sandbox> {
		return this.request('POST', '', body)
	}

	show(id: string): Promise<Sandbox> {
		return this.request('GET', `/${id}`)
	}

	async delete(id: string): Promise<void> {
		await this.request('DELETE', `/${id}`)
	}

	exec(id: string, command: string, timeoutMs: number, signal?: AbortSignal): Promise<ExecResult> {
		return this.request('POST', `/${id}/exec`, { command, timeout_ms: timeoutMs }, signal)
	}

	// A detached command (`/commands`), which outlives any one request.
	startCommand(id: string, body: { command: string; cwd?: string; timeout_ms?: number }): Promise<Command> {
		return this.request('POST', `/${id}/commands`, body)
	}

	cancelCommand(id: string, commandId: string): Promise<Command> {
		return this.request('POST', `/${id}/commands/${commandId}/cancel`)
	}

	// Yields the command's ND-JSON log lines from the given offsets until the
	// server ends the stream; the last line is `exit` or `error` unless the
	// server cut a long stream short.
	async *logs(id: string, commandId: string, offsets: { stdout: number; stderr: number }, signal?: AbortSignal): AsyncGenerator<LogLine> {
		const query = `?stdout_offset=${offsets.stdout}&stderr_offset=${offsets.stderr}`
		const response = await this.send('GET', `/${id}/commands/${commandId}/logs${query}`, undefined, signal, 'application/x-ndjson, application/json')
		if (!response.body) return
		const decoder = new TextDecoder()
		let buffer = ''
		for await (const chunk of response.body) {
			buffer += decoder.decode(chunk as Uint8Array, { stream: true })
			let newline: number
			while ((newline = buffer.indexOf('\n')) >= 0) {
				const line = buffer.slice(0, newline)
				buffer = buffer.slice(newline + 1)
				if (line.trim()) yield JSON.parse(line) as LogLine
			}
		}
	}

	private async request<T>(method: string, path: string, body?: unknown, signal?: AbortSignal): Promise<T> {
		const text = await (await this.send(method, path, body, signal, 'application/json')).text()
		return (text ? JSON.parse(text) : undefined) as T
	}

	private async send(method: string, path: string, body: unknown, signal: AbortSignal | undefined, accept: string): Promise<Response> {
		const url = `${this.serverURL}/api/accounts/${encodeURIComponent(this.account)}/sandboxes${path}`
		const response = await fetch(url, {
			method,
			signal,
			headers: {
				Authorization: `Bearer ${this.token}`,
				Accept: accept,
				...(body === undefined ? {} : { 'Content-Type': 'application/json' }),
			},
			body: body === undefined ? undefined : JSON.stringify(body),
		})
		if (!response.ok) {
			const text = await response.text()
			let message = text.slice(0, 300)
			try {
				message = (JSON.parse(text) as { message?: string }).message ?? message
			} catch {}
			throw new ApiError(`Tuist sandboxes API ${method} ${path.split('?')[0] || '/'} failed (HTTP ${response.status}): ${message}`, response.status)
		}
		return response
	}
}

export class ApiError extends Error {
	constructor(
		message: string,
		readonly status: number,
	) {
		super(message)
	}
}

export interface Command {
	id: string
	status: 'running' | 'exited' | 'timed_out' | 'cancelled' | 'lost'
	exit_code: number | null
}

export type LogLine =
	| { type: 'stdout' | 'stderr'; data: string; offset: number }
	| { type: 'exit'; status: Command['status']; exit_code: number | null }
	| { type: 'error'; message: string }

// A user credential: the sandboxes API needs an account member, which the
// orb's read-only cache token in TUIST_TOKEN is not.
export async function tuistToken(serverURL: string, cwd: string): Promise<string> {
	if (process.env.TUIST_MAC_TOKEN) return process.env.TUIST_MAC_TOKEN
	try {
		return await execText('tuist', ['auth', 'token', '--url', serverURL], { cwd, env: { TUIST_TOKEN: undefined } })
	} catch {
		throw new Error(`Not logged in to ${serverURL}. Run \`tuist auth login --url ${serverURL}\` in the terminal first.`)
	}
}

// The account that owns the sandbox: TUIST_MAC_ACCOUNT, else the account of the
// project's `fullHandle` in Tuist.swift.
export async function accountHandle(root: string): Promise<string> {
	if (process.env.TUIST_MAC_ACCOUNT) return process.env.TUIST_MAC_ACCOUNT
	const manifest = await readFile(join(root, 'Tuist.swift'), 'utf8').catch(() => '')
	const handle = /fullHandle:\s*"([^"/]+)\//.exec(manifest)?.[1]
	if (!handle) throw new Error('Set TUIST_MAC_ACCOUNT, or add a fullHandle to Tuist.swift, to choose the account that owns the Mac.')
	return handle
}
