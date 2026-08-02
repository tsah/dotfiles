import { Database } from "bun:sqlite"
import { randomUUID } from "node:crypto"
import { existsSync, lstatSync, mkdirSync, readFileSync, realpathSync, renameSync, writeFileSync } from "node:fs"
import { dirname, resolve } from "node:path"

export type LineageMode = "off" | "best-effort" | "strict"
export interface LineageIdentity { path: string; commonDir: string; branch: string }
export interface WorkspaceManifest {
  version: 1
  workspaceId: string
  repoId: string
  canonicalPath: string
  commonDir: string
  branch: string
  parentWorkspaceId: string | null
  revision: number
  createdAt: number
  updatedAt: number
}
export interface WorkspaceRecord extends WorkspaceManifest {}
export interface WorkspaceDetails extends WorkspaceRecord {
  parent?: WorkspaceRecord
  children: WorkspaceRecord[]
  exists: boolean
}
export interface WorkspaceTreeNode extends WorkspaceDetails { children: WorkspaceTreeNode[] }
export interface ProjectSnapshot {
  repoId: string
  commonDir: string
  workspaces: WorkspaceRecord[]
}
export interface ReconcileResult {
  repoId: string
  commonDir: string
  workspaces: WorkspaceRecord[]
  removedPaths: string[]
  rewrittenManifestPaths: string[]
}
export interface LineageSnapshot { byPath: Map<string, WorkspaceRecord & { childWorkspaceCount: number }>; byId: Map<string, WorkspaceRecord & { childWorkspaceCount: number }> }

const schemaVersion = 1
const manifestVersion = 1
const manifestRelativePath = ".alt-k/workspace.json"
const manifestIgnoreRule = "/.alt-k/workspace.json"
const defaultStateHome = `${Bun.env.XDG_STATE_HOME || `${Bun.env.HOME || ""}/.local/state`}`
export const workspaceStatePath = `${defaultStateHome}/alt-k-tui/workspaces.sqlite3`

interface RepoRow { id: string; common_dir: string; created_at: number; updated_at: number }
interface WorkspaceRow {
  id: string
  repo_id: string
  canonical_path: string
  branch: string
  parent_id: string | null
  revision: number
  created_at: number
  updated_at: number
}

const canonicalPath = (path: string) => {
  const expanded = path === "~" ? Bun.env.HOME || path : path.startsWith("~/") ? `${Bun.env.HOME}${path.slice(1)}` : path
  try { return realpathSync(expanded) }
  catch { return resolve(expanded) }
}

const altKDirectoryPathFor = (path: string) => `${canonicalPath(path)}/.alt-k`
const manifestPathFor = (path: string) => `${canonicalPath(path)}/${manifestRelativePath}`

const openStore = (dbPath = workspaceStatePath) => {
  mkdirSync(dirname(dbPath), { recursive: true })
  const db = new Database(dbPath, { create: true })
  db.exec("PRAGMA busy_timeout = 5000")
  db.exec("PRAGMA foreign_keys = ON")
  const journalMode = db.query("PRAGMA journal_mode").get() as { journal_mode?: string } | null
  if (journalMode?.journal_mode?.toLowerCase() !== "wal") db.exec("PRAGMA journal_mode = WAL")
  migrate(db)
  return db
}

const migrate = (db: Database) => {
  const current = Number((db.query("PRAGMA user_version").get() as { user_version?: number } | null)?.user_version ?? 0)
  if (current > schemaVersion) throw new Error(`Unsupported workspace lineage store version ${current}`)
  if (current === schemaVersion) return
  if (current === 0) {
    db.exec(`
      CREATE TABLE IF NOT EXISTS repositories (
        id TEXT PRIMARY KEY,
        common_dir TEXT NOT NULL UNIQUE,
        created_at INTEGER NOT NULL,
        updated_at INTEGER NOT NULL
      );
      CREATE TABLE IF NOT EXISTS workspaces (
        id TEXT PRIMARY KEY,
        repo_id TEXT NOT NULL REFERENCES repositories(id) ON DELETE CASCADE,
        canonical_path TEXT NOT NULL UNIQUE,
        branch TEXT NOT NULL,
        parent_id TEXT REFERENCES workspaces(id) ON DELETE SET NULL,
        revision INTEGER NOT NULL,
        created_at INTEGER NOT NULL,
        updated_at INTEGER NOT NULL
      );
      CREATE INDEX IF NOT EXISTS workspaces_repo_id_idx ON workspaces(repo_id);
      CREATE INDEX IF NOT EXISTS workspaces_parent_id_idx ON workspaces(parent_id);
      PRAGMA user_version = 1;
    `)
    return
  }
  throw new Error(`Unsupported workspace lineage store version ${current}`)
}

const rowToRecord = (row: WorkspaceRow & { common_dir?: string; repo_common_dir?: string; commonDir?: string }): WorkspaceRecord => ({
  version: manifestVersion,
  workspaceId: row.id,
  repoId: row.repo_id,
  canonicalPath: row.canonical_path,
  commonDir: row.common_dir || row.repo_common_dir || row.commonDir || "",
  branch: row.branch,
  parentWorkspaceId: row.parent_id,
  revision: row.revision,
  createdAt: row.created_at,
  updatedAt: row.updated_at,
})

const parseManifest = (filePath: string) => {
  let raw: Partial<WorkspaceManifest>
  try { raw = JSON.parse(readFileSync(filePath, "utf8")) as Partial<WorkspaceManifest> }
  catch { throw new Error(`Malformed workspace manifest at ${filePath}`) }
  if (raw.version !== manifestVersion || !raw.workspaceId || !raw.repoId || !raw.canonicalPath || !raw.commonDir || !raw.branch || !Number.isInteger(raw.revision) || !Number.isFinite(raw.createdAt) || !Number.isFinite(raw.updatedAt)) {
    throw new Error(`Malformed workspace manifest at ${filePath}`)
  }
  return {
    version: manifestVersion,
    workspaceId: raw.workspaceId,
    repoId: raw.repoId,
    canonicalPath: canonicalPath(raw.canonicalPath),
    commonDir: canonicalPath(raw.commonDir),
    branch: raw.branch,
    parentWorkspaceId: raw.parentWorkspaceId ?? null,
    revision: Number(raw.revision),
    createdAt: Number(raw.createdAt),
    updatedAt: Number(raw.updatedAt),
  } satisfies WorkspaceManifest
}

const trackedManifest = (path: string) => Bun.spawnSync(["git", "-C", path, "ls-files", "--error-unmatch", "--", manifestRelativePath], { stdout: "ignore", stderr: "ignore" }).exitCode === 0
const lstatSafe = (path: string) => { try { return lstatSync(path) } catch { return undefined } }
const assertManifestParentSafe = (path: string) => {
  const directory = altKDirectoryPathFor(path)
  const stats = lstatSafe(directory)
  if (stats?.isSymbolicLink()) throw new Error(`Workspace manifest directory is a symlink: ${directory}`)
}

const worktreeExcludePath = (path: string) => {
  const result = Bun.spawnSync(["git", "-C", path, "rev-parse", "--git-path", "info/exclude"], { stdout: "pipe", stderr: "pipe" })
  if (result.exitCode !== 0) throw new Error(result.stderr.toString().trim() || `Unable to resolve .git/info/exclude for ${path}`)
  const resolved = result.stdout.toString().trim()
  return resolved.startsWith("/") ? resolved : resolve(path, resolved)
}

const ensureManifestIgnored = (path: string) => {
  assertManifestParentSafe(path)
  const excludePath = worktreeExcludePath(path)
  mkdirSync(dirname(excludePath), { recursive: true })
  const current = existsSync(excludePath) ? readFileSync(excludePath, "utf8") : ""
  const lines = current.split(/\r?\n/).filter(Boolean)
  if (lines.includes(manifestIgnoreRule)) return
  const next = current.length === 0 ? `${manifestIgnoreRule}\n` : current.endsWith("\n") ? `${current}${manifestIgnoreRule}\n` : `${current}\n${manifestIgnoreRule}\n`
  const tmp = `${excludePath}.${process.pid}.${Date.now()}.tmp`
  writeFileSync(tmp, next)
  renameSync(tmp, excludePath)
}

const readLocalManifest = (identity: LineageIdentity) => {
  const manifestPath = manifestPathFor(identity.path)
  assertManifestParentSafe(identity.path)
  if (trackedManifest(canonicalPath(identity.path))) throw new Error(`Refusing to overwrite tracked ${manifestRelativePath} in ${canonicalPath(identity.path)}`)
  const stats = lstatSafe(manifestPath)
  if (!stats) return undefined
  if (stats.isSymbolicLink()) throw new Error(`Workspace manifest is a symlink: ${manifestPath}`)
  const manifest = parseManifest(manifestPath)
  if (manifest.canonicalPath !== canonicalPath(identity.path) || manifest.commonDir !== canonicalPath(identity.commonDir)) {
    throw new Error(`Workspace manifest conflicts with local identity at ${manifestPath}`)
  }
  return manifest
}

const writeManifest = (identity: LineageIdentity, manifest: WorkspaceManifest) => {
  const worktreePath = canonicalPath(identity.path)
  assertManifestParentSafe(worktreePath)
  if (trackedManifest(worktreePath)) throw new Error(`Refusing to overwrite tracked ${manifestRelativePath} in ${worktreePath}`)
  ensureManifestIgnored(worktreePath)
  const target = manifestPathFor(worktreePath)
  const currentStats = lstatSafe(target)
  if (currentStats?.isSymbolicLink()) throw new Error(`Workspace manifest is a symlink: ${target}`)
  if (currentStats) {
    const current = parseManifest(target)
    if (current.workspaceId !== manifest.workspaceId || current.repoId !== manifest.repoId || current.canonicalPath !== manifest.canonicalPath || current.commonDir !== manifest.commonDir) {
      throw new Error(`Workspace manifest conflicts with authoritative lineage at ${target}`)
    }
  }
  mkdirSync(dirname(target), { recursive: true })
  const tmp = `${target}.${process.pid}.${Date.now()}.tmp`
  writeFileSync(tmp, `${JSON.stringify(manifest, null, 2)}\n`)
  renameSync(tmp, target)
}

const repoByCommonDir = (db: Database, commonDir: string) => db.query("SELECT id, common_dir, created_at, updated_at FROM repositories WHERE common_dir = ?1").get(canonicalPath(commonDir)) as RepoRow | null
const workspaceByPath = (db: Database, path: string) => db.query("SELECT id, repo_id, canonical_path, branch, parent_id, revision, created_at, updated_at FROM workspaces WHERE canonical_path = ?1").get(canonicalPath(path)) as WorkspaceRow | null
const workspaceById = (db: Database, id: string) => db.query("SELECT id, repo_id, canonical_path, branch, parent_id, revision, created_at, updated_at FROM workspaces WHERE id = ?1").get(id) as WorkspaceRow | null
const workspaceRowsForRepo = (db: Database, repoId: string, includeCommonDir = false) => db.query(`
  SELECT w.id, w.repo_id, w.canonical_path, w.branch, w.parent_id, w.revision, w.created_at, w.updated_at${includeCommonDir ? ", r.common_dir" : ""}
  FROM workspaces w
  JOIN repositories r ON r.id = w.repo_id
  WHERE w.repo_id = ?1
  ORDER BY w.canonical_path
`).all(repoId) as Array<WorkspaceRow & { common_dir?: string }>

const ensureRepo = (db: Database, commonDir: string, preferredId: string | undefined, now: number) => {
  const canonicalCommonDir = canonicalPath(commonDir)
  const existing = repoByCommonDir(db, canonicalCommonDir)
  if (existing) {
    db.query("UPDATE repositories SET updated_at = ?2 WHERE id = ?1").run(existing.id, now)
    return { ...existing, updated_at: now }
  }
  if (preferredId) {
    const conflict = db.query("SELECT id, common_dir FROM repositories WHERE id = ?1").get(preferredId) as { id: string; common_dir: string } | null
    if (conflict && conflict.common_dir !== canonicalCommonDir) throw new Error(`Repository id ${preferredId} already belongs to ${conflict.common_dir}`)
  }
  const repo: RepoRow = { id: preferredId || randomUUID(), common_dir: canonicalCommonDir, created_at: now, updated_at: now }
  db.query("INSERT INTO repositories (id, common_dir, created_at, updated_at) VALUES (?1, ?2, ?3, ?4)").run(repo.id, repo.common_dir, repo.created_at, repo.updated_at)
  return repo
}

const assertParentAllowed = (db: Database, childId: string, repoId: string, parentId: string | null) => {
  if (!parentId) return
  if (parentId === childId) throw new Error(`Workspace ${childId} cannot parent itself`)
  const parent = workspaceById(db, parentId)
  if (!parent) throw new Error(`Parent workspace ${parentId} does not exist`)
  if (parent.repo_id !== repoId) throw new Error(`Workspace ${childId} cannot attach to parent ${parentId} from another repository`)
  let cursor: WorkspaceRow | null = parent
  const seen = new Set<string>()
  while (cursor) {
    if (cursor.id === childId) throw new Error(`Workspace ${childId} cannot create a lineage cycle`)
    if (!cursor.parent_id || seen.has(cursor.parent_id)) return
    seen.add(cursor.parent_id)
    cursor = workspaceById(db, cursor.parent_id)
  }
}

const upsertWorkspace = (db: Database, identity: LineageIdentity, options: { parentWorkspaceId?: string | null; preserveParent?: boolean; writeProjection?: boolean; preferredManifest?: WorkspaceManifest; now?: number } = {}) => {
  const canonicalIdentity = { ...identity, path: canonicalPath(identity.path), commonDir: canonicalPath(identity.commonDir) }
  const manifest = options.preferredManifest ?? readLocalManifest(canonicalIdentity)
  const now = options.now ?? Date.now()
  const repo = ensureRepo(db, canonicalIdentity.commonDir, manifest?.repoId, now)
  const existing = workspaceByPath(db, canonicalIdentity.path)
  if (manifest?.workspaceId) {
    const conflicting = workspaceById(db, manifest.workspaceId)
    if (conflicting && conflicting.canonical_path !== canonicalIdentity.path) throw new Error(`Workspace id ${manifest.workspaceId} already belongs to ${conflicting.canonical_path}`)
  }
  const workspaceId = existing?.id || manifest?.workspaceId || randomUUID()
  const preserveParent = options.preserveParent !== false
  const desiredParent = options.parentWorkspaceId !== undefined ? options.parentWorkspaceId : preserveParent ? existing?.parent_id ?? manifest?.parentWorkspaceId ?? null : null
  assertParentAllowed(db, workspaceId, repo.id, desiredParent)
  const createdAt = existing?.created_at ?? manifest?.createdAt ?? now
  const previousRevision = existing?.revision ?? manifest?.revision ?? 0
  const changed = !existing || existing.branch !== canonicalIdentity.branch || existing.parent_id !== desiredParent || existing.repo_id !== repo.id
  const revision = changed ? Math.max(1, previousRevision + (existing ? 1 : 0)) : previousRevision || 1
  const record: WorkspaceRecord = {
    version: manifestVersion,
    workspaceId,
    repoId: repo.id,
    canonicalPath: canonicalIdentity.path,
    commonDir: canonicalIdentity.commonDir,
    branch: canonicalIdentity.branch,
    parentWorkspaceId: desiredParent,
    revision,
    createdAt,
    updatedAt: now,
  }
  if (existing) {
    db.query("UPDATE workspaces SET repo_id = ?2, branch = ?3, parent_id = ?4, revision = ?5, updated_at = ?6 WHERE id = ?1").run(record.workspaceId, record.repoId, record.branch, record.parentWorkspaceId, record.revision, record.updatedAt)
  } else {
    db.query("INSERT INTO workspaces (id, repo_id, canonical_path, branch, parent_id, revision, created_at, updated_at) VALUES (?1, ?2, ?3, ?4, ?5, ?6, ?7, ?8)").run(record.workspaceId, record.repoId, record.canonicalPath, record.branch, record.parentWorkspaceId, record.revision, record.createdAt, record.updatedAt)
  }
  if (options.writeProjection !== false) writeManifest(canonicalIdentity, record)
  return record
}

const worktreePathsForRepo = (cwd: string) => {
  const current = identifyWorkspaceSync(cwd)
  const listed = Bun.spawnSync(["git", "-C", current.path, "worktree", "list", "--porcelain"], { stdout: "pipe", stderr: "pipe" })
  if (listed.exitCode !== 0) throw new Error(listed.stderr.toString().trim() || `Unable to list worktrees for ${current.path}`)
  const paths: string[] = []
  for (const line of listed.stdout.toString().split("\n")) {
    if (line.startsWith("worktree ")) paths.push(canonicalPath(line.slice("worktree ".length)))
  }
  return { current, paths }
}

export const lineageMode = (): LineageMode => {
  const mode = Bun.env.DOTFILES_WORKSPACE_LINEAGE || "best-effort"
  return mode === "off" || mode === "strict" ? mode : "best-effort"
}

export const identifyWorkspaceSync = (cwd = process.cwd()): LineageIdentity => {
  const top = Bun.spawnSync(["git", "rev-parse", "--show-toplevel"], { cwd, stdout: "pipe", stderr: "pipe" })
  if (top.exitCode !== 0) throw new Error(top.stderr.toString().trim() || `Unable to resolve worktree for ${cwd}`)
  const path = canonicalPath(top.stdout.toString().trim())
  const common = Bun.spawnSync(["git", "rev-parse", "--git-common-dir"], { cwd: path, stdout: "pipe", stderr: "pipe" })
  if (common.exitCode !== 0) throw new Error(common.stderr.toString().trim() || `Unable to resolve common dir for ${path}`)
  const branch = Bun.spawnSync(["git", "branch", "--show-current"], { cwd: path, stdout: "pipe", stderr: "pipe" })
  if (branch.exitCode !== 0) throw new Error(branch.stderr.toString().trim() || `Unable to resolve branch for ${path}`)
  return { path, commonDir: canonicalPath(resolve(path, common.stdout.toString().trim())), branch: branch.stdout.toString().trim() || "detached" }
}

export const persistWorkspaceLineage = (identity: LineageIdentity, options: { parentWorkspaceId?: string | null; preserveParent?: boolean; mode?: LineageMode; dbPath?: string } = {}) => {
  const mode = options.mode ?? lineageMode()
  if (mode === "off") return undefined
  try {
    return registerWorkspace(identity, { parentWorkspaceId: options.parentWorkspaceId, preserveParent: options.preserveParent, dbPath: options.dbPath })
  } catch (error) {
    if (mode === "strict") throw error
    return undefined
  }
}

export const registerWorkspace = (identity: LineageIdentity, options: { parentWorkspaceId?: string | null; preserveParent?: boolean; dbPath?: string } = {}) => {
  const db = openStore(options.dbPath)
  try {
    return db.transaction(() => upsertWorkspace(db, identity, { parentWorkspaceId: options.parentWorkspaceId, preserveParent: options.preserveParent })).immediate()
  } finally {
    db.close()
  }
}

export const workspaceForPath = (path: string, dbPath = workspaceStatePath) => {
  if (!existsSync(dbPath)) return undefined
  const db = openStore(dbPath)
  try {
    const row = db.query(`
      SELECT w.id, w.repo_id, w.canonical_path, w.branch, w.parent_id, w.revision, w.created_at, w.updated_at, r.common_dir
      FROM workspaces w
      JOIN repositories r ON r.id = w.repo_id
      WHERE w.canonical_path = ?1
    `).get(canonicalPath(path)) as (WorkspaceRow & { common_dir: string }) | null
    return row ? rowToRecord(row) : undefined
  } finally {
    db.close()
  }
}

export const workspaceForId = (id: string, dbPath = workspaceStatePath) => {
  if (!existsSync(dbPath)) return undefined
  const db = openStore(dbPath)
  try {
    const row = db.query(`
      SELECT w.id, w.repo_id, w.canonical_path, w.branch, w.parent_id, w.revision, w.created_at, w.updated_at, r.common_dir
      FROM workspaces w
      JOIN repositories r ON r.id = w.repo_id
      WHERE w.id = ?1
    `).get(id) as (WorkspaceRow & { common_dir: string }) | null
    return row ? rowToRecord(row) : undefined
  } finally {
    db.close()
  }
}

export const attachWorkspaceToParent = (workspaceId: string, parentWorkspaceId: string, dbPath = workspaceStatePath) => {
  const workspace = workspaceForId(workspaceId, dbPath)
  if (!workspace) throw new Error(`Workspace ${workspaceId} does not exist`)
  if (workspace.parentWorkspaceId === parentWorkspaceId) return workspace
  return registerWorkspace({ path: workspace.canonicalPath, commonDir: workspace.commonDir, branch: workspace.branch }, {
    parentWorkspaceId,
    preserveParent: false,
    dbPath,
  })
}

export const detachWorkspaceFromParent = (workspaceId: string, dbPath = workspaceStatePath) => {
  const workspace = workspaceForId(workspaceId, dbPath)
  if (!workspace) throw new Error(`Workspace ${workspaceId} does not exist`)
  if (workspace.parentWorkspaceId === null) return workspace
  return registerWorkspace({ path: workspace.canonicalPath, commonDir: workspace.commonDir, branch: workspace.branch }, {
    parentWorkspaceId: null,
    preserveParent: false,
    dbPath,
  })
}

export const attachmentCandidatesForWorkspace = (workspaceId: string, dbPath = workspaceStatePath) => {
  const workspace = workspaceForId(workspaceId, dbPath)
  if (!workspace) throw new Error(`Workspace ${workspaceId} does not exist`)
  const project = projectSnapshot(workspace.canonicalPath, dbPath)
  const childrenByParent = Map.groupBy(project.workspaces, (candidate) => candidate.parentWorkspaceId || "")
  const blocked = new Set([workspaceId])
  const visitChildren = (parentId: string) => {
    for (const child of childrenByParent.get(parentId) ?? []) {
      if (blocked.has(child.workspaceId)) continue
      blocked.add(child.workspaceId)
      visitChildren(child.workspaceId)
    }
  }
  visitChildren(workspaceId)
  return project.workspaces.filter((candidate) => !blocked.has(candidate.workspaceId) && candidate.workspaceId !== workspace.parentWorkspaceId)
}

export const projectSnapshot = (cwd = process.cwd(), dbPath = workspaceStatePath): ProjectSnapshot => {
  const identity = identifyWorkspaceSync(cwd)
  const db = openStore(dbPath)
  try {
    const repo = repoByCommonDir(db, identity.commonDir)
    if (!repo) return { repoId: "", commonDir: identity.commonDir, workspaces: [] }
    return { repoId: repo.id, commonDir: repo.common_dir, workspaces: workspaceRowsForRepo(db, repo.id, true).map(rowToRecord) }
  } finally {
    db.close()
  }
}

const detailsForRecord = (record: WorkspaceRecord, project: ProjectSnapshot) => ({
  ...record,
  parent: record.parentWorkspaceId ? project.workspaces.find((workspace) => workspace.workspaceId === record.parentWorkspaceId) : undefined,
  children: project.workspaces.filter((workspace) => workspace.parentWorkspaceId === record.workspaceId),
  exists: existsSync(record.canonicalPath),
})

export const workspaceDetails = (cwd = process.cwd(), options: { id?: string; path?: string; dbPath?: string } = {}): WorkspaceDetails | undefined => {
  const dbPath = options.dbPath || workspaceStatePath
  const record = options.id ? workspaceForId(options.id, dbPath) : workspaceForPath(options.path || cwd, dbPath)
  if (!record) return undefined
  return detailsForRecord(record, projectSnapshot(record.canonicalPath, dbPath))
}

export const workspaceTree = (cwd = process.cwd(), dbPath = workspaceStatePath): WorkspaceTreeNode[] => {
  const project = projectSnapshot(cwd, dbPath)
  const byParent = Map.groupBy(project.workspaces, (workspace) => workspace.parentWorkspaceId || "")
  const buildNode = (workspace: WorkspaceRecord): WorkspaceTreeNode => ({
    ...detailsForRecord(workspace, project),
    children: (byParent.get(workspace.workspaceId) ?? []).map(buildNode).sort((a, b) => a.branch.localeCompare(b.branch) || a.canonicalPath.localeCompare(b.canonicalPath)),
  })
  return (byParent.get("") ?? []).map(buildNode).sort((a, b) => a.branch.localeCompare(b.branch) || a.canonicalPath.localeCompare(b.canonicalPath))
}

const emptySnapshot = (): LineageSnapshot => ({ byPath: new Map(), byId: new Map() })

export const readLineageSnapshot = (dbPath = workspaceStatePath, mode: LineageMode = lineageMode()): LineageSnapshot => {
  if (!existsSync(dbPath)) return emptySnapshot()
  try {
    const db = openStore(dbPath)
    try {
      const rows = db.query(`
        SELECT w.id, w.repo_id, w.canonical_path, w.branch, w.parent_id, w.revision, w.created_at, w.updated_at, r.common_dir,
               (SELECT COUNT(*) FROM workspaces child WHERE child.parent_id = w.id) AS child_count
        FROM workspaces w
        JOIN repositories r ON r.id = w.repo_id
      `).all() as Array<WorkspaceRow & { common_dir: string; child_count: number }>
      const byPath = new Map<string, WorkspaceRecord & { childWorkspaceCount: number }>()
      const byId = new Map<string, WorkspaceRecord & { childWorkspaceCount: number }>()
      for (const row of rows) {
        const record = { ...rowToRecord(row), childWorkspaceCount: Number(row.child_count) || 0 }
        byPath.set(record.canonicalPath, record)
        byId.set(record.workspaceId, record)
      }
      return { byPath, byId }
    } finally {
      db.close()
    }
  } catch (error) {
    if (mode === "strict") throw error
    return emptySnapshot()
  }
}

const validateBootstrapManifests = (current: LineageIdentity, manifests: Array<{ identity: LineageIdentity; manifest: WorkspaceManifest }>) => {
  const repoId = manifests[0]?.manifest.repoId
  for (const { identity, manifest } of manifests) {
    if (identity.commonDir !== current.commonDir) throw new Error(`Workspace ${identity.path} belongs to ${identity.commonDir}, not ${current.commonDir}`)
    if (manifest.commonDir !== current.commonDir) throw new Error(`Workspace manifest at ${manifestPathFor(identity.path)} belongs to ${manifest.commonDir}, not ${current.commonDir}`)
    if (repoId && manifest.repoId !== repoId) throw new Error(`Workspace manifests for ${current.commonDir} disagree on repo id`)
  }
}

export const bootstrapRepositoryFromManifests = (cwd = process.cwd(), dbPath = workspaceStatePath): ReconcileResult => {
  const { current, paths } = worktreePathsForRepo(cwd)
  const manifests = paths.map((path) => {
    const identity = identifyWorkspaceSync(path)
    const manifest = readLocalManifest(identity)
    if (!manifest) throw new Error(`Missing workspace manifest at ${manifestPathFor(identity.path)}`)
    return { identity, manifest }
  })
  validateBootstrapManifests(current, manifests)
  const db = openStore(dbPath)
  try {
    return db.transaction(() => {
      const repo = ensureRepo(db, current.commonDir, manifests[0]?.manifest.repoId, Date.now())
      const existingRepo = workspaceRowsForRepo(db, repo.id)
      if (existingRepo.length > 0) throw new Error(`Workspace lineage store already has ${existingRepo.length} row(s) for ${repo.common_dir}; clear it before bootstrap`)
      for (const { identity, manifest } of manifests) upsertWorkspace(db, identity, { preferredManifest: manifest, parentWorkspaceId: null, preserveParent: false, writeProjection: false, now: manifest.updatedAt })
      for (const { identity, manifest } of manifests) upsertWorkspace(db, identity, { preferredManifest: manifest, parentWorkspaceId: manifest.parentWorkspaceId, preserveParent: false, writeProjection: false, now: manifest.updatedAt })
      const workspaces = workspaceRowsForRepo(db, repo.id, true).map(rowToRecord)
      return { repoId: repo.id, commonDir: repo.common_dir, workspaces, removedPaths: [], rewrittenManifestPaths: [] } satisfies ReconcileResult
    }).immediate()
  } finally {
    db.close()
  }
}

export const reconcileRepositoryWorkspaces = (cwd = process.cwd(), dbPath = workspaceStatePath): ReconcileResult => {
  const { current, paths } = worktreePathsForRepo(cwd)
  const identities = paths.map((path) => identifyWorkspaceSync(path))
  const db = openStore(dbPath)
  try {
    return db.transaction(() => {
      const repo = ensureRepo(db, current.commonDir, undefined, Date.now())
      const activePaths = new Set(identities.map((identity) => identity.path))
      const existingRows = workspaceRowsForRepo(db, repo.id)
      const removedPaths = existingRows.filter((row) => !activePaths.has(row.canonical_path)).map((row) => row.canonical_path)
      for (const removedPath of removedPaths) db.query("DELETE FROM workspaces WHERE canonical_path = ?1").run(removedPath)
      const rewrittenManifestPaths: string[] = []
      for (const identity of identities) {
        upsertWorkspace(db, identity, { writeProjection: true })
        rewrittenManifestPaths.push(manifestPathFor(identity.path))
      }
      const workspaces = workspaceRowsForRepo(db, repo.id, true).map(rowToRecord)
      return { repoId: repo.id, commonDir: repo.common_dir, workspaces, removedPaths, rewrittenManifestPaths } satisfies ReconcileResult
    }).immediate()
  } finally {
    db.close()
  }
}
