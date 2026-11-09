import { spawn } from 'node:child_process'

// The Tuist CLI does the work: `tuist sandbox create`, `sync`, `run`,
// `download` and `delete`. The plugin only keeps the thread's sandbox and turns
// the CLI's output into tool results.

// The CLI to run. TUIST_MAC_CLI points at another build, such as one from source.
const CLI = process.env.TUIST_MAC_CLI ?? 'tuist'
// A long log keeps its start and end.
const LOG_HEAD = 20_000
const LOG_TAIL = 200_000

export interface CLIResult {
	exitCode: number
	// stdout and stderr interleaved, as a terminal shows them.
	output: string
	stdout: string
}

export interface CLIOptions {
	cwd: string
	signal?: AbortSignal
}

// The sandbox commands need a user or an account token with `account:sandboxes:use`.
// Orbs set TUIST_TOKEN to a read-only cache token, which has neither, so it is
// replaced with TUIST_MAC_TOKEN, or dropped so the CLI uses `tuist auth login`.
function environment(): NodeJS.ProcessEnv {
	const env = { ...process.env }
	delete env.TUIST_TOKEN
	if (process.env.TUIST_MAC_TOKEN) env.TUIST_TOKEN = process.env.TUIST_MAC_TOKEN
	return env
}

function accountArguments(): string[] {
	return process.env.TUIST_MAC_ACCOUNT ? ['--account', process.env.TUIST_MAC_ACCOUNT] : []
}

// Runs `tuist sandbox <args>` and returns its exit code and combined output.
// An abort sends SIGINT, which makes `tuist sandbox exec` cancel the command in
// the sandbox before it exits.
export function sandbox(args: string[], { cwd, signal }: CLIOptions): Promise<CLIResult> {
	const [subcommand, ...rest] = args
	const separator = rest.indexOf('--')
	const options = separator < 0 ? rest : rest.slice(0, separator)
	const trailing = separator < 0 ? [] : rest.slice(separator)
	return new Promise((resolve, reject) => {
		const child = spawn(CLI, ['sandbox', subcommand, ...options, ...accountArguments(), ...trailing], {
			cwd,
			env: environment(),
			stdio: ['ignore', 'pipe', 'pipe'],
		})
		const output = new HeadTail()
		const stdout = new HeadTail()
		child.stdout.on('data', (chunk: Buffer) => {
			output.push(chunk.toString())
			stdout.push(chunk.toString())
		})
		child.stderr.on('data', (chunk: Buffer) => output.push(chunk.toString()))
		const onAbort = () => child.kill('SIGINT')
		signal?.addEventListener('abort', onAbort, { once: true })
		child.on('error', (error: NodeJS.ErrnoException) => {
			signal?.removeEventListener('abort', onAbort)
			reject(error.code === 'ENOENT' ? new Error(`The Tuist CLI (${CLI}) is not installed. Install it with \`mise use -g tuist@latest\`.`) : error)
		})
		child.on('close', (code, killSignal) => {
			signal?.removeEventListener('abort', onAbort)
			const text = output.text()
			if (/Unexpected argument|unknown subcommand|Unknown option|Error: Unknown/i.test(text) && code !== 0 && ['sync', 'exec', 'cp'].includes(subcommand)) {
				reject(new Error(`This Tuist CLI has no \`tuist sandbox ${subcommand}\`. Update it with \`mise use -g tuist@latest\`.\n${text}`))
				return
			}
			resolve({ exitCode: code ?? (killSignal === 'SIGINT' ? 130 : 1), output: text, stdout: stdout.text() })
		})
	})
}

// Runs a CLI step that must succeed and returns its parsed `--json` output.
export async function sandboxJSON<T>(args: string[], opts: CLIOptions): Promise<T> {
	const result = await sandbox([...args, '--json'], opts)
	if (result.exitCode !== 0) {
		// On Linux the CLI reads the account from tuist.toml only; Tuist.swift needs a Swift toolchain.
		const hint = result.output.includes('Pass --account')
			? '\nSet TUIST_MAC_ACCOUNT to the Tuist account handle, or add a tuist.toml with `project = "<account>/<project>"`.'
			: ''
		throw new Error(`tuist sandbox ${args[0]} failed:\n${result.output.slice(-4000)}${hint}`)
	}
	return JSON.parse(result.stdout) as T
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
