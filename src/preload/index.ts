import type { WorkspaceData, WorkspaceCommand } from '../core/workspace';
import type { LectureConnectInput, LectureRef } from '../core/lectures';
/**
 * Preload: the only bridge between the renderer and the network layer.
 * Nothing here exposes Node or the session cookie to web content.
 */

import { contextBridge, ipcRenderer } from 'electron';

const api = {
  lectures: {
    state: (account: number) => ipcRenderer.invoke('lectures:state', account),
    connect: (account: number, input: LectureConnectInput) => ipcRenderer.invoke('lectures:connect', account, input),
    disconnect: (account: number) => ipcRenderer.invoke('lectures:disconnect', account),
    sync: (account: number) => ipcRenderer.invoke('lectures:sync', account),
    bind: (account: number, icourseCourseId: string, canvasCourseId: number | null) => ipcRenderer.invoke('lectures:bind', account, icourseCourseId, canvasCourseId),
    list: (account: number, courseId: number, query = '', offset = 0) => ipcRenderer.invoke('lectures:list', account, courseId, query, offset),
    detail: (account: number, ref: LectureRef) => ipcRenderer.invoke('lectures:detail', account, ref),
    read: (account: number, ref: LectureRef) => ipcRenderer.invoke('lectures:read', account, ref),
    onUpdated: (cb: () => void) => { const listener = () => cb(); ipcRenderer.on('lectures:updated', listener); return () => ipcRenderer.removeListener('lectures:updated', listener); },
  },
  course: {
    introduction: (account: number, courseId: number, force = false) => ipcRenderer.invoke('course:introduction', account, courseId, force),
  },
  workspace: {
    get: (account: number) => ipcRenderer.invoke('workspace:get', account),
    mutate: (account: number, command: WorkspaceCommand) => ipcRenderer.invoke('workspace:mutate', account, command),
    onUpdated: (cb: () => void) => { const listener = () => cb(); ipcRenderer.on('workspace:updated', listener); return () => ipcRenderer.removeListener('workspace:updated', listener); },
    onNavigate: (cb: (target: Record<string, string>) => void) => { const listener = (_e: unknown, target: Record<string, string>) => cb(target); ipcRenderer.on('workspace:navigate', listener); return () => ipcRenderer.removeListener('workspace:navigate', listener); },
  },
  prefs: {
    get: () => ipcRenderer.invoke('prefs:get'),
    set: (patch: Record<string, unknown>) => ipcRenderer.invoke('prefs:set', patch),
  },
  auth: {
    prepare: (username: string) => ipcRenderer.invoke('auth:prepare', username),
    checkCaptcha: (username: string) => ipcRenderer.invoke('auth:checkCaptcha', username),
    submit: (payload: { username: string; password: string; captchaCode?: string; remember?: boolean; useRememberedPassword?: boolean }) =>
      ipcRenderer.invoke('auth:submit', payload),
    status: () => ipcRenderer.invoke('auth:status'),
    remembered: () => ipcRenderer.invoke('auth:remembered'),
    logout: () => ipcRenderer.invoke('auth:logout'),
  },
  data: {
    snapshot: (opts?: { force?: boolean; full?: boolean }) => ipcRenderer.invoke('data:snapshot', opts ?? {}),
    cached: () => ipcRenderer.invoke('data:cached'),
    clear: () => ipcRenderer.invoke('data:clear'),
    onProgress: (cb: (p: { done: number; total: number; label: string }) => void) => {
      const listener = (_e: unknown, payload: { done: number; total: number; label: string }) => cb(payload);
      ipcRenderer.on('data:progress', listener);
      return () => ipcRenderer.removeListener('data:progress', listener);
    },
  },
  files: {
    course: (courseId: number, force?: boolean) =>
      ipcRenderer.invoke('files:course', { courseId, force: force === true }),
    download: (courseId: number, fileIds?: number[]) =>
      ipcRenderer.invoke('files:download', { courseId, fileIds }),
    cancel: () => ipcRenderer.invoke('files:cancel'),
    root: () => ipcRenderer.invoke('files:root'),
    pickRoot: () => ipcRenderer.invoke('files:pickRoot'),
    reveal: (relativePath: string) => ipcRenderer.invoke('files:reveal', relativePath),
    onProgress: (cb: (p: unknown) => void) => {
      const listener = (_e: unknown, payload: unknown) => cb(payload);
      ipcRenderer.on('files:progress', listener);
      return () => ipcRenderer.removeListener('files:progress', listener);
    },
  },
  assignment: {
    /** 按需拉完整描述，并给出 100 字以内简介（有缓存则直接返回）。 */
    detail: (courseId: number, assignmentId: number) =>
      ipcRenderer.invoke('assignment:detail', { courseId, assignmentId }),
    /** 手头已有描述时只算简介。 */
    summarise: (payload: { assignmentId: number; name: string; description: string }) =>
      ipcRenderer.invoke('assignment:summarise', payload),
  },
  llm: {
    get: () => ipcRenderer.invoke('llm:get'),
    set: (patch: Record<string, unknown>) => ipcRenderer.invoke('llm:set', patch),
  },
  open: (url: string) => ipcRenderer.invoke('shell:open', url),
  version: () => ipcRenderer.invoke('app:version'),
  onResume: (callback: () => void) => { const listener = () => callback(); ipcRenderer.on('app:resume', listener); return () => ipcRenderer.removeListener('app:resume', listener); },
};

contextBridge.exposeInMainWorld('elearning', api);

export type ElearningApi = typeof api;
