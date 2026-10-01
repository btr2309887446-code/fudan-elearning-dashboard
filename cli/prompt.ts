/** Tiny terminal prompt helpers (hidden input for passwords). */

import { createInterface } from 'node:readline';

export function ask(question: string): Promise<string> {
  const rl = createInterface({ input: process.stdin, output: process.stdout });
  return new Promise((resolve) => {
    rl.question(question, (answer) => {
      rl.close();
      resolve(answer.trim());
    });
  });
}

/**
 * Read a line without echoing it. In raw mode a paste can arrive as one chunk,
 * so the chunk is walked character by character.
 */
export function askHidden(question: string): Promise<string> {
  const stdin = process.stdin;
  const stdout = process.stdout;

  if (!stdin.isTTY || typeof stdin.setRawMode !== 'function') {
    return ask(question);
  }

  return new Promise((resolve) => {
    stdout.write(question);
    stdin.setRawMode(true);
    stdin.resume();
    stdin.setEncoding('utf8');

    let buffer = '';

    const finish = (value: string) => {
      stdin.setRawMode(false);
      stdin.pause();
      stdin.removeListener('data', onData);
      stdout.write('\n');
      resolve(value);
    };

    const onData = (chunk: string) => {
      for (const ch of chunk) {
        if (ch === '\r' || ch === '\n' || ch === '\u0004') return finish(buffer);
        if (ch === '\u0003') {
          // Ctrl-C
          stdin.setRawMode(false);
          stdout.write('\n');
          process.exit(130);
        }
        if (ch === '\u007f' || ch === '\b') {
          buffer = buffer.slice(0, -1);
          continue;
        }
        if (ch === '\u001b') continue; // ignore escape sequences
        if (ch >= ' ') buffer += ch;
      }
    };

    stdin.on('data', onData);
  });
}
