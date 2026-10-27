import {
  existsSync,
  mkdirSync,
  readFileSync,
  writeFileSync,
  renameSync,
  copyFileSync,
} from "node:fs";
import { join } from "node:path";
import { randomUUID } from "node:crypto";
import {
  emptyWorkspace,
  mutateWorkspace,
  recordChanges,
  type WorkspaceData,
  type WorkspaceCommand,
  type ResourceResult,
} from "../core/workspace.ts";

export function atomicJson(path: string, value: unknown): void {
  const temporary = `${path}.${randomUUID()}.tmp`;
  writeFileSync(temporary, JSON.stringify(value), {
    encoding: "utf8",
    flush: true,
  });
  if (existsSync(path)) copyFileSync(path, `${path}.bak`);
  renameSync(temporary, path);
}
export class WorkspaceStore {
  private root: string;
  constructor(root: string) {
    this.root = root;
    mkdirSync(root, { recursive: true });
  }
  private path(account: number) {
    if (!Number.isSafeInteger(account) || account < 0)
      throw new Error("账号无效");
    return join(this.root, `workspace-${account}.json`);
  }
  read(account: number): WorkspaceData {
    const path = this.path(account);
    if (!existsSync(path)) return emptyWorkspace(account);
    const data = JSON.parse(readFileSync(path, "utf8")) as WorkspaceData;
    if (
      data.version !== 1 ||
      data.account !== account ||
      !Array.isArray(data.series) ||
      !data.baselines ||
      !data.deadlines
    )
      throw new Error("本地任务文件格式异常，原文件已保留");
    return data;
  }
  write(data: WorkspaceData) {
    atomicJson(this.path(data.account), data);
    return data;
  }
  mutate(account: number, command: WorkspaceCommand) {
    return this.write(mutateWorkspace(this.read(account), command, randomUUID));
  }
  ingest(account: number, results: ResourceResult[], at: string) {
    return this.write(
      recordChanges(this.read(account), results, randomUUID(), at, randomUUID),
    );
  }
}
