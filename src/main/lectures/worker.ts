import { parentPort, workerData } from 'node:worker_threads';
import { LectureEngine, decodeIndex, derivePassword } from './engine.ts';
const engine = new LectureEngine(workerData.wasmPath, workerData.sourceId);
// A single queue prevents async WASM initialization from racing subsequent reads.
let queue = Promise.resolve();
parentPort!.on('message', ({ id, method, args }: { id: number; method: string; args: unknown[] }) => {
  queue = queue.then(async () => {
    try {
      let value: unknown;
      if (method === 'index') value = decodeIndex(args[0] as Uint8Array, args[1] as string);
      else if (method === 'derive') value = derivePassword(args[0] as string, args[1] as string);
      else if (['load', 'courses', 'list', 'body', 'resources', 'demo', 'retain', 'close'].includes(method))
        value = await (engine[method as keyof LectureEngine] as (...a: unknown[]) => unknown).apply(engine, args);
      else throw new Error('未知课堂内容操作');
      parentPort!.postMessage({ id, value });
    } catch (error) { parentPort!.postMessage({ id, error: error instanceof Error ? error.message : '课堂内容处理失败' }); }
  });
});
