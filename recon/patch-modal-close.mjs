/**
 * 给两个弹层加退场动画：关闭时先播 closing 再真正卸载。
 *
 * 直接卸载会让弹层「啪」地消失，和入场动画不对称。
 *
 *   node recon/patch-modal-close.mjs
 */

import { readFileSync, writeFileSync } from 'node:fs';

const files = [
  'D:/vit/杂/elearning/src/renderer/src/components/AssignmentDetail.tsx',
  'D:/vit/杂/elearning/src/renderer/src/components/SettingsModal.tsx',
];

for (const p of files) {
  let s = readFileSync(p, 'utf8');
  const name = p.split('/').pop();

  // 1) import：加 useRef，加 closeWithAnimation
  s = s.replace(
    "import { useEffect, useState } from 'react';",
    "import { useEffect, useRef, useState } from 'react';"
  );
  s = s.replace(
    "import Icon from './Icon';",
    "import { closeWithAnimation } from '../motion';\nimport Icon from './Icon';"
  );

  // 2) 在组件体开头插入 ref 与 requestClose
  const bodyStart = s.indexOf('}: Props) {');
  const braceEnd = s.indexOf('\n', bodyStart);
  const insert = [
    '',
    '  // 退场动画期间先别卸载：直接消失和入场动画不对称。',
    '  const backdropRef = useRef<HTMLDivElement>(null);',
    '  const closing = useRef(false);',
    '',
    '  function requestClose() {',
    '    if (closing.current) return;',
    '    closing.current = true;',
    '    closeWithAnimation(backdropRef.current, onClose);',
    '  }',
  ].join('\n');
  s = s.slice(0, braceEnd) + insert + s.slice(braceEnd);

  // 3) 所有关闭入口改走 requestClose
  s = s.replace("if (e.key === 'Escape') onClose();", "if (e.key === 'Escape') requestClose();");
  s = s.replace('}, [onClose]);', '}, [requestClose]);');
  s = s.replace('<div className="modal-backdrop" onClick={onClose}>', '<div className="modal-backdrop" ref={backdropRef} onClick={requestClose}>');
  s = s.replace('onClick={onClose} title="关闭（Esc）"', 'onClick={requestClose} title="关闭（Esc）"');
  s = s.replace('onClick={onClose}>\n            关闭', 'onClick={requestClose}>\n            关闭');
  s = s.replace('<button className="btn" onClick={onClose}>', '<button className="btn" onClick={requestClose}>');

  writeFileSync(p, s, 'utf8');

  const left = (s.match(/onClick=\{onClose\}|onClose\(\);/g) ?? []).length;
  console.log(`${name}: 剩余直接调 onClose 的地方 ${left} 处`);
}
