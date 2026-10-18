// Fleet kill guard: the one rule every runtime adapter calls (pi, opencode, and this file's CLI for the Claude hook).
// A kill, pkill or killall may signal only the caller's own descendants, never PID 1, the systemd user manager or the
// herdr server, and never a target it cannot resolve. A block is final.
import { readdirSync, readFileSync } from "node:fs";
import { basename } from "node:path";
import { fileURLToPath } from "node:url";

const SELF = fileURLToPath(import.meta.url);
const KILLERS = { kill: "lL", pkill: "fxicnoea", killall: "erqvwyl" }; // each command's single-letter options
const WRAPPERS = /^(sudo|env|nohup|exec|command|builtin|time|nice|timeout|setsid|xargs|then|do|else|if|while|until)$/;
const SIGNAL = /^-(\d+|[A-Z][A-Z0-9]*)$/; // -9, -KILL, -SIGTERM

// Simple commands, split on ; | & and newlines outside quotes.
function segments(command) {
	const out = [""];
	for (let i = 0, q = ""; i < command.length; i++) {
		const c = command[i];
		if (!q && ";|&\n".includes(c)) out.push("");
		else if (c === "\\" && q !== "'") out[out.length - 1] += c + (command[++i] ?? "");
		else {
			if (c === q) q = "";
			else if (!q && (c === '"' || c === "'")) q = c;
			out[out.length - 1] += c;
		}
	}
	return out;
}

const words = (s) => (s.match(/(?:"[^"]*"|'[^']*'|\S)+/g) ?? []).map((t) => t.replace(/"([^"]*)"|'([^']*)'/g, "$1$2"));

// The command word past assignments and wrappers: `nice -n 5 kill 1` is a kill of 1. xargs means the targets come from stdin.
function commandOf(w) {
	let i = 0, piped = false;
	for (; i < w.length && (/^[A-Za-z_]\w*=|^[-\d.]/.test(w[i]) || WRAPPERS.test(w[i])); i++) piped ||= w[i] === "xargs";
	return { words: w.slice(i), piped };
}

// Every process from /proc. Throws when /proc cannot be read: the guard then cannot run.
function procTable() {
	const table = new Map();
	for (const d of readdirSync("/proc").filter((d) => /^\d+$/.test(d))) {
		try {
			const stat = readFileSync(`/proc/${d}/stat`, "utf8");
			table.set(+d, {
				pid: +d,
				ppid: +stat.slice(stat.lastIndexOf(")") + 2).split(" ")[1],
				comm: readFileSync(`/proc/${d}/comm`, "utf8").trim(),
				argv: readFileSync(`/proc/${d}/cmdline`, "utf8").split("\0").filter(Boolean),
			});
		} catch {} // exited while listed
	}
	return table;
}

// The caller's own processes: every descendant of root, never root itself.
function descendants(table, root) {
	const kids = new Map();
	for (const p of table.values()) kids.set(p.ppid, [...(kids.get(p.ppid) ?? []), p.pid]);
	const own = new Set(), todo = [root];
	while (todo.length) for (const c of kids.get(todo.pop()) ?? []) if (!own.has(c)) { own.add(c); todo.push(c); }
	return own;
}

// Why a process may not be signalled, or null when the caller started it.
function reasonFor(p, own) {
	if (p.missing) return `PID ${p.pid} (no such process)`;
	if (p.pid === 1) return "PID 1 (init)";
	if (p.comm === "systemd" && p.argv.includes("--user")) return `PID ${p.pid} (the systemd user manager)`;
	if (p.comm === "herdr" && p.argv.includes("server")) return `PID ${p.pid} (the herdr server)`;
	return own.has(p.pid) ? null : `PID ${p.pid} (${p.comm}), which this task did not start`;
}

// The block for one kill, pkill or killall, or null when every process it would signal is the caller's own.
function judge(name, args, text, caller, procs) {
	const flags = [], ops = [];
	for (let i = 0; i < args.length; i++) {
		const a = args[i];
		if (a === "--") { ops.push(...args.slice(i + 1)); break; }
		if (a === "-s" || (name === "kill" && a === "-n")) i++;
		else if (!ops.length && SIGNAL.test(a)) continue;
		else if (/^-[a-zA-Z]+$/.test(a)) flags.push(...a.slice(1));
		else ops.push(a);
	}
	const unresolved = (why) => `"${text}" cannot be resolved to processes: ${why}`;
	if (flags.some((f) => !KILLERS[name].includes(f))) return unresolved("an option the guard does not read");
	if (name === "kill" && flags.length) return null; // kill -l lists signal names and signals nothing
	if (!ops.length) return null; // no operand: nothing to signal
	let hits;
	if (name === "kill") {
		const bad = ops.find((a) => !/^[1-9]\d*$/.test(a));
		if (bad !== undefined) return unresolved(`"${bad}" is not a PID`);
		hits = ops.map((a) => procs().get(+a) ?? { pid: +a, missing: true });
	} else {
		if (ops.some((o) => /[$`]/.test(o))) return unresolved("the pattern is set by the shell");
		let test;
		try {
			if (name === "pkill") {
				const re = new RegExp(flags.includes("x") ? `^(?:${ops[0]})$` : ops[0], flags.includes("i") ? "i" : "");
				test = (p) => re.test(flags.includes("f") ? p.argv.join(" ") : p.comm);
			} else {
				const res = ops.map((n) => (flags.includes("r") ? new RegExp(n) : n));
				test = (p) => res.some((n) => (n instanceof RegExp ? n.test(p.comm) : p.comm === n || basename(p.argv[0] ?? "") === n));
			}
		} catch {
			return unresolved("the pattern is not one the guard can read");
		}
		hits = [...procs().values()].filter(test);
	}
	const reason = hits.map((p) => reasonFor(p, descendants(procs(), caller))).find((r) => r);
	return reason ? `"${text}" aims at ${reason}` : null;
}

// The first kill, pkill or killall in the command (also inside sh -c, eval, $( ) or backticks) aimed outside the caller's tree.
function blockedBy(command, caller, procs) {
	for (const seg of segments(command)) {
		const text = seg.trim().replace(/^[\s({!]+/, "");
		const inner = [...text.matchAll(/\$\(([^()]*)\)|`([^`]*)`/g)].map((m) => m[1] ?? m[2]);
		const { words: w, piped } = commandOf(words(text));
		const name = w.length ? basename(w[0]).replace(/^\\/, "") : "";
		const t = inner.map((c) => blockedBy(c, caller, procs)).find(Boolean) ??
			(/^(ba|z|da)?sh$/.test(name) && /^-\w*c$/.test(w[1] ?? "") && w[2] ? blockedBy(w[2], caller, procs) :
			name === "eval" ? blockedBy(w.slice(1).join(" "), caller, procs) :
			!Object.hasOwn(KILLERS, name) ? null :
			piped ? `"${text}" cannot be resolved to processes: its targets come from xargs` :
			judge(name, w.slice(1), text, caller, procs));
		if (t) return t;
	}
	return null;
}

// Returns the block message, or null to allow. caller is the process whose descendants may be signalled: in-process
// adapters leave it at this process, the Claude hook passes the agent's pid. If the guard cannot run, it warns and allows.
export function guard(command, { caller = process.pid } = {}) {
	let target, table;
	try {
		target = blockedBy(String(command ?? ""), caller, () => (table ??= procTable()));
	} catch (e) {
		process.stderr.write(`kill guard could not run, allowing the command: ${e.message}\n`);
		return null;
	}
	if (target === null) return null;
	return (
		`BLOCKED by the fleet kill guard: ${target}. Kill only process IDs you started yourself in this task; never PID 1, the systemd user manager, ` +
		`the herdr server, or a process found by name or pattern that you did not start. This block is final: do not retry it, reword it, or work around it. ` +
		`If another process is in your way, write \`blocked:\` naming it and stop.`
	);
}

// Hook CLI for Claude Code: PreToolUse JSON on stdin; exit 2 with the reason on stderr blocks. --caller is the agent's pid
// (the hook command passes $PPID); without it the caller is the hook's parent shell, which blocks more.
if (process.argv[1] === SELF) {
	let p = {};
	try { p = JSON.parse(readFileSync(0, "utf8")); } catch {}
	const arg = (flag) => { const i = process.argv.indexOf(flag); return i > 1 ? process.argv[i + 1] : undefined; };
	const reason = guard(p?.tool_input?.command, { caller: Number(arg("--caller")) || process.ppid });
	if (reason !== null) { process.stderr.write(reason + "\n"); process.exit(2); }
}
