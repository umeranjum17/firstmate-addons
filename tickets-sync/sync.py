#!/usr/bin/env python3
"""Read-only tasks-axi backfill and incremental publication via sign-off-axi ticket."""
import datetime as dt
import fcntl
import hashlib
import json
import os
from pathlib import Path
import re
import subprocess as sp
import sys
import time
import tomllib

sys.path.insert(0, str(Path(__file__).resolve().parents[1] / 'fleet-dashboard'))
from task_rows import toon_rows, plain

def run(args, env=None, cwd=None):
    r = sp.run(args, env=env, cwd=cwd, text=True, capture_output=True, timeout=60)
    if r.returncode:
        raise RuntimeError(f'{args[0]}: {r.stderr.strip() or r.stdout.strip()}')
    return r.stdout

def rows(args, env, cwd=None):
    text = run(args + ['--limit', '100000', '--fields', 'held,hold_kind,closed,priority,body,links'], env, cwd)
    result = toon_rows(text)
    if result is None or re.search(r'count: \d+ of (?!0\b)\d+ total', text) and len(result) >= 100000:
        raise RuntimeError('tasks-axi returned an unreadable or capped task list')
    return result

def ticket_id(home, item):
    return "fm-" + hashlib.sha256(f"{home}/{item}".encode()).hexdigest()[:32]

def sync():
    started = time.monotonic()
    home = Path(os.environ['FM_HOME']).resolve()
    board = Path((home / 'config/fleet-board').read_text().strip())
    if not board.is_absolute(): board = home / board
    state = home / 'state/tickets-sync'
    state.mkdir(parents=True, exist_ok=True)
    with (state / 'lock').open('w') as lock:
        fcntl.flock(lock, fcntl.LOCK_EX)
        (state / '.tasks.toml').write_text('[markdown]\narchive="unused-archive.md"\n')
        current = {t['id']: t for t in json.loads(run(['sign-off-axi', 'ticket', str(board), '--json']))['tickets']}
        parents = {t.get('parent') for t in current.values()}
        homes = {'main': home}
        registry = home / 'data/secondmates.md'
        for line in registry.read_text().splitlines() if registry.exists() else []:
            m = re.match(r'- (\S+) - .*\(home: ([^;]+);', line)
            if m: homes[m[1]] = Path(m[2])
            elif re.match(r'- \S+ - .*\(host:', line): raise RuntimeError('remote home requires a tasks-axi reader: ' + line.split(' - ')[1])
        parked_file = home / 'config/parked-homes'
        parked = {l.split('#')[0].strip() for l in parked_file.read_text().splitlines()} if parked_file.exists() else set()
        cutoff = (dt.date.today() - dt.timedelta(days=7)).isoformat()
        changed = gaps = 0
        for name, source in homes.items():
            env = {k: v for k, v in os.environ.items() if k not in ('FM_DATA_OVERRIDE', 'FM_ROOT_OVERRIDE', 'TASKS_AXI_FILE', 'TASKS_AXI_BACKEND')}
            env['FM_HOME'] = str(source)
            reader = ['bash', str(home / 'bin/fm-tasks-axi.sh')]
            tasks = rows(reader + ['list'], env) + rows(reader + ['list', '--state', 'done'], env)
            address = run(['bash', '-c', '. "$1/fm-tasks-axi-lib.sh"; . "$1/fm-backlog-transition-lib.sh"; fm_backlog_tasks_axi_addressing "$FM_HOME/data" || exit; printf "%s\\n%s\\n" "$FM_BACKLOG_AXI_ROOT" "$FM_BACKLOG_AXI_FILE"', 'tickets-sync', str(home / 'bin')], env).splitlines()
            root, file = address
            if not file: raise RuntimeError(f'{name}: archive backfill requires markdown addressing')
            settings = {}
            for config in (Path.home() / '.tasks-axi/config.toml', Path(root) / '.tasks.toml'):
                if config.exists(): settings.update(tomllib.loads(config.read_text()).get('markdown', {}))
            archive = Path(root) / settings.get('archive', str(Path(file).parent / 'done-archive.md'))
            archive_copy = state / f'{name}-archive.md'
            if archive.exists():
                archive_copy.write_text(re.sub(r'^## Archived[^\n]*$', '## Done', archive.read_text(), flags=re.M))
            archived = rows(['tasks-axi', 'list', '--state', 'done', '--backend', 'markdown', '--file', str(archive_copy)], env, state) if archive.exists() else []
            tasks = {r['id']: r for r in archived + tasks}.values()
            for r in tasks:
                if time.monotonic() - started > 20:
                    print('tickets-sync: backfill continuing on next watcher check')
                    return
                tid = ticket_id(name, r['id'])
                if r['state'] == 'done' and r.get('closed', '-') < cutoff and tid not in current: continue
                if '\n... (truncated, ' in r['title'] + r.get('body', ''):
                    full = run(reader + ['show', r['id'], '--full'], env) if r not in archived else run(['tasks-axi', 'show', r['id'], '--full', '--file', str(archive_copy)], env, state)
                    for key, value in re.findall(r'^  (title|body): (.*)$', full, re.M): r[key] = json.loads(value) if value.startswith('"') else value
                body = r.get('body', '')
                def field(key):
                    m = re.search(r'^\s*' + key + r':\s*(.+)$', body, re.M | re.I)
                    return m[1].strip() if m else ''
                held = name in parked or r.get('held') == 'yes' or r.get('hold_kind') == 'parked'
                done = r['state'] == 'done'
                progress = 100 if done else 0 if held or r['state'] == 'queued' else 17
                label = 'Done' if done else 'On hold' if held else 'To do' if r['state'] == 'queued' else 'In progress'
                links = re.findall(r'https?://[^\s,\]\)]+', r.get('links', '') + '\n' + r['title'] + '\n' + body)
                size = lambda text: len(text.encode('utf-16-le')) // 2
                detail = [label, (field('release') or 'later')[:64]]
                links = list(dict.fromkeys(links))
                while links and size(' · '.join(detail + links)) > 115:
                    links.pop(); gaps += 1
                suffix = ' · ' + ' · '.join(detail + links)
                title = plain(re.sub(r'https?://\S+', '', r['title']).strip())
                room = 160 - size(suffix)
                title = (title.encode('utf-16-le')[:2*(room-1)].decode('utf-16-le', errors='ignore').rstrip() + '…' if size(title) > room else title) + suffix
                parent = field('parent') or field('epic')
                desired = dict(title=title, progress=progress, parent=ticket_id(name, parent) if parent else '', priority=f"P{r['priority']}" if str(r.get('priority')) in ('0', '1', '2', '3') else '', project=r.get('repo', '') if r.get('repo') != '-' else name, hold='yes' if held and not done else 'no', asked='yes' if '[captain-ask]' in r['title'] else 'no')
                old = current.get(tid, {})
                if all(k == 'progress' and tid in parents or old.get(k, '') == (v == 'yes' if k in ('hold', 'asked') else v) for k, v in desired.items()): continue
                args = ['sign-off-axi', 'ticket', str(board), '--id', tid]
                for key, value in desired.items(): args += ['--' + key, str(value)]
                run(args)
                changed += 1
        if changed: print(f'tickets-sync: {len(homes)} homes read; {changed} tickets changed; {gaps} links exceed the public title limit')

if __name__ == '__main__':
    try: sync()
    except (OSError, ValueError, KeyError, RuntimeError, sp.TimeoutExpired) as error:
        print(f'tickets-sync: {error}', file=sys.stderr)
        sys.exit(1)
