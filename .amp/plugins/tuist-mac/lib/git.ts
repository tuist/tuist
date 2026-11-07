import { copyFile, mkdtemp, rm } from 'node:fs/promises'
import { tmpdir } from 'node:os'
import { join } from 'node:path'
import { exec, execText } from './run.ts'

export async function headCommit(root: string): Promise<string> {
	return execText('git', ['rev-parse', 'HEAD'], { cwd: root })
}

// Where the Mac fetches the base commit from: origin, as an anonymous HTTPS URL.
export async function originURL(root: string): Promise<string> {
	const url = await execText('git', ['config', '--get', 'remote.origin.url'], { cwd: root })
	const github = /github\.com[/:]([^/]+)\/(.+?)(?:\.git)?$/.exec(url)
	return github ? `https://github.com/${github[1]}/${github[2]}.git` : url
}

// The worktree's difference from `base`: tracked changes plus untracked files
// that are not ignored, as a binary patch. Uses a scratch index so the user's
// staging area is untouched.
export async function worktreePatch(root: string, base: string): Promise<Buffer> {
	const dir = await mkdtemp(join(tmpdir(), 'tuist-mac-'))
	const index = join(dir, 'index')
	try {
		const realIndex = await execText('git', ['rev-parse', '--path-format=absolute', '--git-path', 'index'], { cwd: root })
		const env = { GIT_INDEX_FILE: index }
		try {
			await copyFile(realIndex, index)
		} catch {
			await exec('git', ['read-tree', base], { cwd: root, env })
		}
		await exec('git', ['add', '-A'], { cwd: root, env })
		return await exec('git', ['diff', '--cached', '--binary', '--no-color', '--no-ext-diff', base], { cwd: root, env })
	} finally {
		await rm(dir, { recursive: true, force: true })
	}
}

// Mac-side script that makes the session workspace match `base` plus the patch.
// It moves the worktree with a two-tree `read-tree -m -u`, which rewrites only
// files whose content differs, so Xcode's incremental build keeps the rest.
// Untracked, non-ignored files the Mac created are removed, as in a mirror;
// ignored ones (build products, DerivedData under the repo) stay.
export function syncScript(base: string, patchFile: string): string {
	return `set -euo pipefail
test -f ${patchFile}
export GIT_INDEX_FILE=/tmp/tuist-mac/target.index
rm -f "$GIT_INDEX_FILE"
git read-tree ${base}
if [ -s ${patchFile} ]; then git apply --cached --binary --whitespace=nowarn ${patchFile}; fi
target=$(git write-tree)
unset GIT_INDEX_FILE
git add -A
current=$(git write-tree)
git read-tree -m -u "$current" "$target"
git reset -q
echo "synced to $target"
`
}

// Mac-side script that puts the base commit in dir. A shallow fetch of one commit,
// without credentials, so the repository must be readable anonymously.
export function checkoutScript(dir: string, url: string, base: string): string {
	return `set -euo pipefail
mkdir -p ${dir}
cd ${dir}
git init -q
git remote add origin ${url} 2>/dev/null || git remote set-url origin ${url}
git -c protocol.version=2 fetch -q --depth 1 --no-tags origin ${base}
git checkout -q --detach ${base}
`
}
