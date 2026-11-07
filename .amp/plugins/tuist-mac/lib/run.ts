import { execFile } from 'node:child_process'

export interface ExecOptions {
	cwd?: string
	env?: Record<string, string | undefined>
	input?: string | Buffer
}

// Runs a program without a shell and returns stdout as a Buffer, so binary
// diffs survive. Rejects with stderr on a non-zero exit.
export function exec(file: string, args: string[], opts: ExecOptions = {}): Promise<Buffer> {
	return new Promise((resolve, reject) => {
		const env = { ...process.env, ...opts.env }
		for (const [k, v] of Object.entries(env)) if (v === undefined) delete env[k]
		const child = execFile(
			file,
			args,
			{ cwd: opts.cwd, env: env as Record<string, string>, encoding: 'buffer', maxBuffer: 512 * 1024 * 1024 },
			(error, stdout, stderr) => {
				if (error) {
					const message = stderr.toString().trim() || error.message
					reject(new Error(`${file} ${args[0] ?? ''} failed: ${message}`))
				} else {
					resolve(stdout)
				}
			},
		)
		if (opts.input !== undefined) child.stdin?.end(opts.input)
	})
}

export async function execText(file: string, args: string[], opts: ExecOptions = {}): Promise<string> {
	return (await exec(file, args, opts)).toString().trim()
}
