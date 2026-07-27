import { afterEach, describe, expect, test } from "bun:test"
import { Database } from "bun:sqlite"
import { existsSync, mkdirSync, readFileSync, readdirSync, rmSync, symlinkSync, unlinkSync, writeFileSync } from "node:fs"
import { mkdtempSync } from "node:fs"
import { tmpdir } from "node:os"
import { dirname, join, resolve } from "node:path"
import { bootstrapRepositoryFromManifests, identifyWorkspaceSync, persistWorkspaceLineage, projectSnapshot, readLineageSnapshot, reconcileRepositoryWorkspaces, registerWorkspace, workspaceDetails, workspaceTree } from "./lineage"

const roots: string[] = []
afterEach(() => {
  for (const root of roots.splice(0)) rmSync(root, { recursive: true, force: true })
})

const tempRoot = (name: string) => {
  const root = mkdtempSync(join(tmpdir(), `${name}-`))
  roots.push(root)
  return root
}

const run = (argv: string[], cwd?: string) => {
  const result = Bun.spawnSync(argv, { cwd, stdout: "pipe", stderr: "pipe" })
  if (result.exitCode !== 0) throw new Error(result.stderr.toString().trim() || `${argv.join(" ")} exited ${result.exitCode}`)
  return result.stdout.toString().trim()
}

const git = (cwd: string, ...args: string[]) => run(["git", ...args], cwd)

const createRepo = (root: string, name = "repo") => {
  const repo = join(root, name)
  mkdirSync(repo, { recursive: true })
  git(root, "init", "-q", "-b", "main", repo)
  git(repo, "config", "user.name", "Workspace Lineage QA")
  git(repo, "config", "user.email", "workspace-lineage@example.invalid")
  writeFileSync(join(repo, "fixture.txt"), "fixture\n")
  git(repo, "add", "fixture.txt")
  git(repo, "commit", "-qm", "Initial fixture")
  return repo
}

const addWorktree = (repo: string, branch: string, worktreePath: string) => {
  git(repo, "worktree", "add", "-q", "-b", branch, worktreePath)
  return worktreePath
}

const fixture = () => {
  const root = tempRoot("alt-k-lineage")
  const dbPath = join(root, "state", "workspaces.sqlite3")
  const repo = createRepo(root)
  const child = addWorktree(repo, "child", join(root, "child"))
  const grandchild = addWorktree(repo, "grandchild", join(root, "grandchild"))
  return {
    root,
    dbPath,
    repo,
    workspaces: {
      main: identifyWorkspaceSync(repo),
      child: identifyWorkspaceSync(child),
      grandchild: identifyWorkspaceSync(grandchild),
    },
  }
}

const manifestPath = (path: string) => join(path, ".alt-k", "workspace.json")
const excludePath = (path: string) => {
  const resolved = run(["git", "-C", path, "rev-parse", "--git-path", "info/exclude"])
  return resolved.startsWith("/") ? resolved : resolve(path, resolved)
}
const manifest = (path: string) => JSON.parse(readFileSync(manifestPath(path), "utf8")) as { workspaceId: string; parentWorkspaceId: string | null; revision: number }

describe("workspace lineage store", () => {
  test("runs migrations once and keeps registration idempotent", () => {
    const { dbPath, workspaces } = fixture()
    mkdirSync(dirname(dbPath), { recursive: true })
    const db = new Database(dbPath, { create: true })
    db.exec("PRAGMA user_version = 0")
    db.close()

    const first = registerWorkspace(workspaces.main, { dbPath })
    const second = registerWorkspace(workspaces.main, { dbPath })
    const reopened = new Database(dbPath, { create: true })
    expect(reopened.query("PRAGMA user_version").get()).toEqual({ user_version: 1 })
    reopened.close()
    expect(second.workspaceId).toBe(first.workspaceId)
    expect(second.revision).toBe(first.revision)
  })

  test("rejects newer schema versions", () => {
    const { dbPath, workspaces } = fixture()
    mkdirSync(dirname(dbPath), { recursive: true })
    const db = new Database(dbPath, { create: true })
    db.exec("PRAGMA user_version = 2")
    db.close()

    expect(() => registerWorkspace(workspaces.main, { dbPath })).toThrow(/version 2/)
  })

  test("builds nested A → B → C lineage", () => {
    const { dbPath, workspaces } = fixture()
    const main = registerWorkspace(workspaces.main, { dbPath })
    const child = registerWorkspace(workspaces.child, { dbPath, parentWorkspaceId: main.workspaceId })
    const grandchild = registerWorkspace(workspaces.grandchild, { dbPath, parentWorkspaceId: child.workspaceId })

    const details = workspaceDetails(workspaces.child.path, { dbPath })!
    expect(details.parent?.workspaceId).toBe(main.workspaceId)
    expect(details.children.map((workspace) => workspace.workspaceId)).toEqual([grandchild.workspaceId])
    expect(workspaceTree(workspaces.main.path, dbPath).map((node) => node.workspaceId)).toEqual([main.workspaceId])
    expect(workspaceTree(workspaces.main.path, dbPath)[0]?.children[0]?.workspaceId).toBe(child.workspaceId)
    expect(workspaceTree(workspaces.main.path, dbPath)[0]?.children[0]?.children[0]?.workspaceId).toBe(grandchild.workspaceId)
  })

  test("rejects self cycles, lineage cycles, and cross-repo parents", () => {
    const { dbPath, workspaces } = fixture()
    const main = registerWorkspace(workspaces.main, { dbPath })
    const child = registerWorkspace(workspaces.child, { dbPath, parentWorkspaceId: main.workspaceId })
    const grandchild = registerWorkspace(workspaces.grandchild, { dbPath, parentWorkspaceId: child.workspaceId })
    expect(() => registerWorkspace(workspaces.main, { dbPath, parentWorkspaceId: main.workspaceId })).toThrow(/cannot parent itself/)
    expect(() => registerWorkspace(workspaces.main, { dbPath, parentWorkspaceId: grandchild.workspaceId })).toThrow(/cycle/)

    const otherRoot = tempRoot("alt-k-other")
    const otherRepo = createRepo(otherRoot, "other")
    const other = registerWorkspace(identifyWorkspaceSync(otherRepo), { dbPath })
    expect(() => registerWorkspace(workspaces.child, { dbPath, parentWorkspaceId: other.workspaceId })).toThrow(/another repository/)
  })

  test("reparents a child while keeping one active parent", () => {
    const { dbPath, workspaces } = fixture()
    const main = registerWorkspace(workspaces.main, { dbPath })
    const child = registerWorkspace(workspaces.child, { dbPath, parentWorkspaceId: main.workspaceId })
    const grandchild = registerWorkspace(workspaces.grandchild, { dbPath, parentWorkspaceId: main.workspaceId })

    const reparents = registerWorkspace(workspaces.grandchild, { dbPath, parentWorkspaceId: child.workspaceId })
    expect(reparents.parentWorkspaceId).toBe(child.workspaceId)
    expect(reparents.revision).toBe(grandchild.revision + 1)
    expect(workspaceDetails(workspaces.main.path, { dbPath })!.children.map((workspace) => workspace.workspaceId)).toEqual([child.workspaceId])
    expect(workspaceDetails(workspaces.child.path, { dbPath })!.children.map((workspace) => workspace.workspaceId)).toEqual([grandchild.workspaceId])
  })

  test("writes a clean ignored manifest atomically and refuses unsafe conflicts", () => {
    const { dbPath, repo, workspaces } = fixture()
    const main = registerWorkspace(workspaces.main, { dbPath })
    expect(existsSync(manifestPath(workspaces.main.path))).toBe(true)
    expect(manifest(workspaces.main.path).workspaceId).toBe(main.workspaceId)
    expect(readFileSync(excludePath(workspaces.main.path), "utf8").match(/\/\.alt-k\/workspace\.json/g)?.length).toBe(1)
    expect(git(repo, "status", "--porcelain", "--untracked-files=all")).not.toContain(".alt-k/workspace.json")
    expect(run(["git", "-C", repo, "check-ignore", "-v", ".alt-k/workspace.json"])).toContain(".git/info/exclude")

    const child = registerWorkspace(workspaces.child, { dbPath, parentWorkspaceId: main.workspaceId })
    const cleared = registerWorkspace(workspaces.child, { dbPath, parentWorkspaceId: null })
    expect(cleared.revision).toBe(child.revision + 1)
    expect(manifest(workspaces.child.path).parentWorkspaceId).toBeNull()
    expect(readdirSync(join(workspaces.child.path, ".alt-k")).filter((entry) => entry.includes(".tmp"))).toEqual([])

    unlinkSync(manifestPath(workspaces.child.path))
    writeFileSync(manifestPath(workspaces.child.path), "tracked\n")
    git(workspaces.child.path, "add", "-f", ".alt-k/workspace.json")
    expect(() => registerWorkspace(workspaces.child, { dbPath })).toThrow(/tracked/)
    git(workspaces.child.path, "reset", "HEAD", ".alt-k/workspace.json")

    unlinkSync(manifestPath(workspaces.child.path))
    symlinkSync(join(workspaces.main.path, ".gitignore"), manifestPath(workspaces.child.path))
    expect(() => registerWorkspace(workspaces.child, { dbPath })).toThrow(/symlink/)
    unlinkSync(manifestPath(workspaces.child.path))

    rmSync(join(workspaces.child.path, ".alt-k"), { recursive: true, force: true })
    symlinkSync(join(workspaces.main.path, ".git"), join(workspaces.child.path, ".alt-k"))
    expect(() => registerWorkspace(workspaces.child, { dbPath })).toThrow(/directory is a symlink/)
    unlinkSync(join(workspaces.child.path, ".alt-k"))
    mkdirSync(join(workspaces.child.path, ".alt-k"), { recursive: true })

    writeFileSync(manifestPath(workspaces.child.path), "{\n")
    expect(() => registerWorkspace(workspaces.child, { dbPath })).toThrow(/Malformed/)

    writeFileSync(manifestPath(workspaces.child.path), JSON.stringify({
      version: 1,
      workspaceId: child.workspaceId,
      repoId: child.repoId,
      canonicalPath: workspaces.main.path,
      commonDir: workspaces.child.commonDir,
      branch: workspaces.child.branch,
      parentWorkspaceId: null,
      revision: child.revision,
      createdAt: child.createdAt,
      updatedAt: child.updatedAt,
    }, null, 2))
    expect(() => registerWorkspace(workspaces.child, { dbPath })).toThrow(/conflicts with local identity/)
  })

  test("repairs missing manifests from the database", () => {
    const { dbPath, workspaces } = fixture()
    const main = registerWorkspace(workspaces.main, { dbPath })
    const child = registerWorkspace(workspaces.child, { dbPath, parentWorkspaceId: main.workspaceId })
    unlinkSync(manifestPath(workspaces.child.path))
    expect(existsSync(manifestPath(workspaces.child.path))).toBe(false)

    const reconciled = reconcileRepositoryWorkspaces(workspaces.main.path, dbPath)
    expect(reconciled.rewrittenManifestPaths).toContain(manifestPath(workspaces.child.path))
    expect(manifest(workspaces.child.path).parentWorkspaceId).toBe(child.parentWorkspaceId)
  })

  test("bootstraps an empty database from manifests", () => {
    const { dbPath, workspaces } = fixture()
    const main = registerWorkspace(workspaces.main, { dbPath })
    const child = registerWorkspace(workspaces.child, { dbPath, parentWorkspaceId: main.workspaceId })
    const grandchild = registerWorkspace(workspaces.grandchild, { dbPath, parentWorkspaceId: child.workspaceId })
    const before = projectSnapshot(workspaces.main.path, dbPath)
    rmSync(dbPath, { force: true })

    const bootstrapped = bootstrapRepositoryFromManifests(workspaces.main.path, dbPath)
    const after = projectSnapshot(workspaces.main.path, dbPath)
    expect(bootstrapped.workspaces.map((workspace) => workspace.workspaceId).sort()).toEqual(before.workspaces.map((workspace) => workspace.workspaceId).sort())
    expect(workspaceTree(workspaces.main.path, dbPath)[0]?.children[0]?.children[0]?.workspaceId).toBe(grandchild.workspaceId)
    expect(after.workspaces.find((workspace) => workspace.canonicalPath === workspaces.child.path)?.parentWorkspaceId).toBe(main.workspaceId)
  })

  test("bootstrap rejects inconsistent manifests before mutating the store", () => {
    const { dbPath, workspaces } = fixture()
    const main = registerWorkspace(workspaces.main, { dbPath })
    const child = registerWorkspace(workspaces.child, { dbPath, parentWorkspaceId: main.workspaceId })
    registerWorkspace(workspaces.grandchild, { dbPath, parentWorkspaceId: child.workspaceId })
    rmSync(dbPath, { force: true })

    const childManifest = {
      ...manifest(workspaces.child.path),
      version: 1,
      workspaceId: child.workspaceId,
      repoId: `${child.repoId}-other`,
      canonicalPath: workspaces.child.path,
      commonDir: workspaces.child.commonDir,
      branch: workspaces.child.branch,
      parentWorkspaceId: main.workspaceId,
      createdAt: child.createdAt,
      updatedAt: child.updatedAt,
    }
    writeFileSync(manifestPath(workspaces.child.path), `${JSON.stringify(childManifest, null, 2)}\n`)

    expect(() => bootstrapRepositoryFromManifests(workspaces.main.path, dbPath)).toThrow(/disagree on repo id/)
    expect(existsSync(dbPath)).toBe(false)

    childManifest.repoId = child.repoId
    childManifest.commonDir = `${workspaces.child.commonDir}-other`
    writeFileSync(manifestPath(workspaces.child.path), `${JSON.stringify(childManifest, null, 2)}\n`)
    expect(() => bootstrapRepositoryFromManifests(workspaces.main.path, dbPath)).toThrow(/belongs to|conflicts with local identity/)
    expect(existsSync(dbPath)).toBe(false)
  })

  test("supports best-effort and off modes without disrupting callers", () => {
    const { dbPath, workspaces } = fixture()
    mkdirSync(join(workspaces.main.path, ".alt-k"), { recursive: true })
    writeFileSync(manifestPath(workspaces.main.path), "{\n")

    expect(persistWorkspaceLineage(workspaces.main, { dbPath, mode: "best-effort" })).toBeUndefined()
    expect(readLineageSnapshot(dbPath).byPath.size).toBe(0)
    expect(persistWorkspaceLineage(workspaces.main, { dbPath, mode: "off" })).toBeUndefined()
    expect(readLineageSnapshot(dbPath).byPath.size).toBe(0)
    expect(() => persistWorkspaceLineage(workspaces.main, { dbPath, mode: "strict" })).toThrow(/Malformed/)
  })

  test("readLineageSnapshot fails open by default and throws in strict mode", () => {
    const root = tempRoot("alt-k-lineage-bad-db")
    const dbPath = join(root, "state", "workspaces.sqlite3")
    mkdirSync(dirname(dbPath), { recursive: true })
    const db = new Database(dbPath, { create: true })
    db.exec("PRAGMA user_version = 2")
    db.close()

    expect(readLineageSnapshot(dbPath).byPath.size).toBe(0)
    expect(() => readLineageSnapshot(dbPath, "strict")).toThrow(/version 2/)
  })

  test("exposes child counts through the lineage snapshot", () => {
    const { dbPath, workspaces } = fixture()
    const main = registerWorkspace(workspaces.main, { dbPath })
    registerWorkspace(workspaces.child, { dbPath, parentWorkspaceId: main.workspaceId })
    registerWorkspace(workspaces.grandchild, { dbPath, parentWorkspaceId: main.workspaceId })
    expect(readLineageSnapshot(dbPath).byPath.get(workspaces.main.path)?.childWorkspaceCount).toBe(2)
  })
})
