#!/usr/bin/env python3
"""Append redacted captain messages from Claude JSONL transcripts."""
import datetime as dt
import json
import os
from pathlib import Path
import re
import subprocess
import sys


def redact(text):
    patterns = [
        r'(?i)\b(?:pin|passcode|password|passwd|token|api[_ -]?key|secret|key|credential|code|pairing code|sign[- ]?in code|verification code)\b\s*[:=]\s*\S+',
        r'(?i)\b(?:pin|passcode|password|passwd|token|api[_ -]?key|secret|key|credential|code|pairing code|sign[- ]?in code|verification code)\b\s+is\s+\S+',
        r'(?i)\b(?:sk-[A-Za-z0-9_-]{8,}|gh[pousr]_[A-Za-z0-9_]{8,}|xox[baprs]-[A-Za-z0-9-]{8,}|Bearer\s+\S+|eyJ[A-Za-z0-9_-]+\.[A-Za-z0-9_-]+\.[A-Za-z0-9_-]+|[A-Fa-f0-9]{32,}|[A-Za-z0-9+/]{40,}={0,2})',
        r'(?i)\b\d{4,8}\b',
    ]
    for p in patterns:
        text = re.sub(p, '[redacted]', text)
    return text


def extract_text(content):
    if isinstance(content, str):
        return content
    if isinstance(content, list):
        return '\n'.join(str(x.get('text', '')) for x in content if isinstance(x, dict) and x.get('type') == 'text')
    return ''


def clean(text):
    if re.search(r'(?is)<(?:command-name|local-command-stdout|local-command-stderr|local-command-caveat)>', text):
        return ''
    text = re.sub(r'(?is)<(?:system-reminder|firstmate-instruction|firstmate-operational-input)>.*?</(?:system-reminder|firstmate-instruction|firstmate-operational-input)>', '', text)
    kept = []
    for line in text.splitlines():
        s = line.strip()
        s = re.split(r'(?i)(?:^|\s)(?:system:|hook:|notification:|firstmate instruction waiting|firstmate operational input)\b', s, maxsplit=1)[0].strip()
        if not s or re.match(r'(?i)^(system|hook|notification|firstmate instruction waiting|firstmate operational input|local-command|<local-command|<command-|/\w+)', s):
            continue
        if re.match(r'(?i)^(reminder|<system-reminder|<firstmate)', s):
            continue
        kept.append(s)
    return ' '.join(kept)


def main():
    home = Path(os.environ.get('FM_HOME', str(Path.home() / 'firstmate'))).resolve()
    transcripts = Path(os.environ.get('CHAT_TSV_TRANSCRIPTS', str(Path.home() / '.claude/projects/-home-umer-firstmate')))
    dest = home / 'data/chat.tsv'
    sidecar = home / 'data/chat.tsv.seen'
    if len(sys.argv) not in (1, 3):
        raise SystemExit('usage: chat-tsv.py [YYYY-MM-DD YYYY-MM-DD]')
    start = dt.date.fromisoformat(sys.argv[1]) if len(sys.argv) == 3 else None
    end = dt.date.fromisoformat(sys.argv[2]) if len(sys.argv) == 3 else None
    if not transcripts.is_dir():
        raise SystemExit(f'transcripts directory missing: {transcripts}')
    check = subprocess.run(['git', '-C', str(home), 'check-ignore', '-q', str(dest)], check=False)
    if check.returncode != 0:
        raise SystemExit(f'refusing: {dest} is not gitignored')
    data = dest.parent
    data.mkdir(parents=True, exist_ok=True, mode=0o700)
    os.chmod(data, 0o700)
    seen = set(sidecar.read_text().splitlines()) if sidecar.exists() else set()
    rows = []
    ids = []
    for file in sorted(transcripts.glob('*.jsonl')):
        for raw in file.read_text(errors='replace').splitlines():
            try:
                rec = json.loads(raw)
                msg = rec.get('message', {})
                if rec.get('type') != 'user' or rec.get('isMeta') or rec.get('isSidechain') or msg.get('role') != 'user':
                    continue
                uid = msg.get('id') or rec.get('uuid')
                if not uid or uid in seen:
                    continue
                body = clean(extract_text(msg.get('content')))
                if not body:
                    continue
                if re.match(r'(?i)^(system|hook|notification|firstmate instruction waiting|firstmate operational input)', body):
                    continue
                stamp = dt.datetime.fromisoformat(rec['timestamp'].replace('Z', '+00:00')).astimezone(dt.timezone.utc)
                if start and not start <= stamp.date() <= end:
                    continue
                cwd = rec.get('cwd', '')
                work = Path(cwd).name if cwd and Path(cwd).name not in ('firstmate', '') else 'main'
                text = redact(body).replace('\t', ' ').replace('\n', ' ')
                rows.append((stamp.isoformat().replace('+00:00', 'Z'), work, text))
                ids.append(uid)
            except (ValueError, TypeError, KeyError):
                continue
    with dest.open('a', encoding='utf-8') as out:
        for row in rows:
            out.write('\t'.join(row) + '\n')
    os.chmod(dest, 0o600)
    with sidecar.open('a', encoding='utf-8') as out:
        for uid in ids:
            out.write(uid + '\n')
    os.chmod(sidecar, 0o600)
    print(f'appended {len(rows)} rows')


if __name__ == '__main__':
    main()
