import { describe, expect, test } from "bun:test"
import { parseArgs } from "./cli"

describe("cli argument parsing", () => {
  test("takes flag values without consuming later flags", () => {
    const parsed = parseArgs(["worker", "--parent", "workspace-123", "branch", "prompt"])
    expect(parsed.shift()).toBe("worker")
    expect(parsed.take("--parent")).toBe("workspace-123")
    expect(parsed.args).toEqual(["branch", "prompt"])
  })

  test("rejects missing values and next-flag values", () => {
    expect(() => parseArgs(["session", "--cwd"]).take("--cwd")).toThrow(/requires a value/)
    expect(() => parseArgs(["worker", "--parent", "--wait", "branch", "prompt"]).take("--parent")).toThrow(/requires a value/)
  })
})
