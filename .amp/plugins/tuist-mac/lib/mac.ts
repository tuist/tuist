import { randomBytes } from 'node:crypto'
import type { SandboxClient } from './sandbox.ts'

// Commands run on the Mac through the sandbox exec API. One exec is a single
// HTTP request, and tuist.dev's proxy ends a response after about 100 seconds,
// well short of a build. So a command starts in its own session (outside the
// exec's process group, which the guest kills when the exec returns), and
// short execs wait for it in turns of WAIT_SECONDS.
//
// PROTOTYPE: this deliberately steps outside the exec's process-group fence. A
// server-side asynchronous exec (start, then poll or stream by command ID)
// would replace it.
const WAIT_SECONDS = 50
const STATE = '/tmp/tuist-mac'
// Kept under macOS's ARG_MAX (1 MiB for argv and environment), since the
// guest runs every exec as `/bin/bash -lc <command>`.
const CHUNK = 256 * 1024
// The exec API caps each stream at 1 MiB; ask for less.
const LOG_HEAD = 20_000
const LOG_TAIL = 200_000

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
		const result = await this.client.exec(this.sandboxId, command, timeoutMs, signal)
		return { exitCode: result.exit_code ?? 124, output: result.stdout + result.stderr }
	}

	// Runs `script` with bash in `cwd` until it ends or `timeoutMs` passes,
	// however long that is, and returns its combined output.
	async run(script: string, { cwd, timeoutMs, signal }: { cwd: string; timeoutMs: number; signal?: AbortSignal }): Promise<RunResult> {
		const dir = `${STATE}/${randomBytes(8).toString('hex')}`
		await this.upload(`${dir}/cmd.sh`, Buffer.from(script))
		const launch =
			`set -e; cd ${quote(cwd)}; ` +
			// perl's setsid gives the command its own session and process group.
			`perl -MPOSIX -e 'POSIX::setsid(); exec @ARGV or die' -- /bin/bash -c ` +
			quote(`echo $$ > "$1/pid"; /bin/bash "$1/cmd.sh" > "$1/log" 2>&1 < /dev/null; echo $? > "$1/exit.tmp"; mv "$1/exit.tmp" "$1/exit"`) +
			` _ ${dir} > /dev/null 2>&1 < /dev/null &\n`
		const deadline = Date.now() + timeoutMs
		let first = true
		const onAbort = () => void this.exec(`kill -TERM -- -$(cat ${dir}/pid) 2>/dev/null; true`).catch(() => {})
		signal?.addEventListener('abort', onAbort, { once: true })
		try {
			for (;;) {
				signal?.throwIfAborted()
				const wait = Math.max(1, Math.min(WAIT_SECONDS, Math.ceil((deadline - Date.now()) / 1000)))
				const result = await this.exec(`${first ? launch : ''}${waitScript(dir, wait)}`, (wait + 30) * 1000, signal)
				first = false
				const done = /^__TM_EXIT_(\d+)__\n/.exec(result.output)
				if (done) return { exitCode: Number(done[1]), output: result.output.slice(done[0].length) }
				if (!result.output.startsWith('__TM_RUNNING__')) throw new Error(`Lost track of the Mac command:\n${result.output.slice(0, 2000)}`)
				if (Date.now() >= deadline) {
					await this.exec(`kill -TERM -- -$(cat ${dir}/pid) 2>/dev/null; true`).catch(() => {})
					throw new Error(`Mac command timed out after ${Math.round(timeoutMs / 1000)}s`)
				}
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

// Waits up to `seconds` for the command, then prints its exit code and log,
// or a marker that it is still running. A long log keeps its start and end.
function waitScript(dir: string, seconds: number): string {
	return `d=${dir}; end=$((SECONDS + ${seconds}))
while [ ! -f "$d/exit" ] && [ "$SECONDS" -lt "$end" ]; do sleep 0.2; done
if [ ! -f "$d/exit" ]; then echo __TM_RUNNING__; exit 0; fi
echo "__TM_EXIT_$(cat "$d/exit")__"
size=$(wc -c < "$d/log" | tr -d ' ')
if [ "$size" -gt ${LOG_HEAD + LOG_TAIL} ]; then
  head -c ${LOG_HEAD} "$d/log"; printf '\\n… %s bytes omitted …\\n' "$((size - ${LOG_HEAD + LOG_TAIL}))"; tail -c ${LOG_TAIL} "$d/log"
else cat "$d/log"; fi
rm -rf "$d"
`
}

export function quote(value: string): string {
	return `'${value.replace(/'/g, `'\\''`)}'`
}
