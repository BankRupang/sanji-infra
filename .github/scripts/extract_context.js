#!/usr/bin/env node
// Usage: node .github/scripts/extract_context.js <changed_files> <diff_file>

const fs = require('fs');

const [,, changedFilesPath, diffFilePath] = process.argv;

if (!changedFilesPath || !diffFilePath) {
  console.error('Error: Usage: node extract_context.js <changed_files> <diff_file>');
  process.exit(1);
}
if (!fs.existsSync(changedFilesPath) || !fs.existsSync(diffFilePath)) {
  console.error('Error: Required input files not found.');
  process.exit(1);
}

// diff.txt를 1회만 파싱해 파일별 hunk 시작 줄을 수집
// (파일 수만큼 diff를 반복 스캔하는 O(N×M) 문제 해결)
const fileHunks = new Map();
let currentFile = null;

for (const line of fs.readFileSync(diffFilePath, 'utf8').split('\n')) {
  if (line.startsWith('diff --git ')) {
    const match = line.match(/ b\/(.+)$/);
    if (match) {
      // 따옴표로 감싸진 경로(공백/특수문자 포함) 처리
      currentFile = match[1].replace(/^"(.+)"$/, '$1');
    }
  } else if (currentFile && line.startsWith('@@ ')) {
    const match = line.match(/\+(\d+)/);
    if (match) {
      if (!fileHunks.has(currentFile)) fileHunks.set(currentFile, []);
      fileHunks.get(currentFile).push(parseInt(match[1], 10));
    }
  }
}

// hunk 시작 줄 목록을 받아 겹치는 구간을 병합한 범위 배열 반환
function mergeRanges(hunkStarts, totalLines) {
  const DECLARATION_END = 80;
  const BEFORE = 30;
  const AFTER = 100;

  const ranges = hunkStarts
    .slice()
    .sort((a, b) => a - b)
    .map(s => ({
      start: Math.max(s - BEFORE, DECLARATION_END + 1),
      end: Math.min(s + AFTER, totalLines),
    }))
    .filter(r => r.start <= r.end);

  return ranges.reduce((merged, r) => {
    if (merged.length === 0 || r.start > merged[merged.length - 1].end) {
      merged.push({ ...r });
    } else {
      merged[merged.length - 1].end = Math.max(merged[merged.length - 1].end, r.end);
    }
    return merged;
  }, []);
}

const changedFiles = fs.readFileSync(changedFilesPath, 'utf8')
  .split('\n')
  .map(f => f.trim())  // CRLF(\r\n) 및 앞뒤 공백 제거
  .filter(Boolean);

for (const file of changedFiles) {
  if (!fs.existsSync(file)) continue;

  const lines = fs.readFileSync(file, 'utf8').split('\n');
  const totalLines = lines.length;

  console.log(`=== FULL FILE: ${file} ===`);

  if (totalLines <= 500) {
    console.log(lines.join('\n'));
  } else {
    console.log(`[파일 크기: ${totalLines}줄 - 선언부 및 변경 구간만 표시]`);
    console.log('--- 선언부 (1-80줄) ---');
    console.log(lines.slice(0, 80).join('\n'));

    const ranges = mergeRanges(fileHunks.get(file) || [], totalLines);
    for (const { start, end } of ranges) {
      console.log(`\n--- 변경 구간 (${start}-${end}줄) ---`);
      console.log(lines.slice(start - 1, end).join('\n'));
    }
  }

  console.log(`=== END FILE: ${file} ===\n`);
}
