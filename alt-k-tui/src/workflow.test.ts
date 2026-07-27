import { describe, expect, test } from "bun:test"
import { resolveWorkerParent } from "./workflow"

describe("worker parent resolution", () => {
  const missingParentId = "00000000-0000-4000-8000-000000000001"

  test("rejects explicit parents when lineage is off", async () => {
    await expect(resolveWorkerParent({ parentWorkspaceId: missingParentId }, "off")).rejects.toThrow(/does not support --parent/)
  })

  test("rejects unknown explicit parents in enabled modes", async () => {
    await expect(resolveWorkerParent({ parentWorkspaceId: missingParentId }, "best-effort")).rejects.toThrow(/Unknown workspace parent id/)
    await expect(resolveWorkerParent({ parentWorkspaceId: missingParentId }, "strict")).rejects.toThrow(/Unknown workspace parent id/)
  })
})
