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
// also uses. Every call needs an account administrator's user token.
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

	private async request<T>(method: string, path: string, body?: unknown, signal?: AbortSignal): Promise<T> {
		const url = `${this.serverURL}/api/accounts/${encodeURIComponent(this.account)}/sandboxes${path}`
		const response = await fetch(url, {
			method,
			signal,
			headers: {
				Authorization: `Bearer ${this.token}`,
				Accept: 'application/json',
				...(body === undefined ? {} : { 'Content-Type': 'application/json' }),
			},
			body: body === undefined ? undefined : JSON.stringify(body),
		})
		const text = await response.text()
		if (!response.ok) {
			let message = text.slice(0, 300)
			try {
				message = (JSON.parse(text) as { message?: string }).message ?? message
			} catch {}
			throw new Error(`Tuist sandboxes API ${method} ${path || '/'} failed (HTTP ${response.status}): ${message}`)
		}
		return (text ? JSON.parse(text) : undefined) as T
	}
}

// A user credential: the sandboxes API needs an account administrator, which the
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
