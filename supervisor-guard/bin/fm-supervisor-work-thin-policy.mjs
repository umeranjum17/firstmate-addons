#!/usr/bin/env node
// Supervisor-work rules: no crew-owned no-mistakes run, no sleep or poll inside a
// turn, and no raw pane typing by a secondmate lead. The shell lexer comes from
// the Firstmate checkout named by --code-root, so nothing upstream is copied here.
// Prints `allow`, or `deny<TAB><code><TAB><reason>`; a failure exits 1 (fail-open).

import * as path from "node:path";
import * as url from "node:url";

const REASONS = {
  "supervisor-no-mistakes-run":
    "a supervisor never drives a crew-owned no-mistakes run: the worker that started it owns the run. Read its status with `no-mistakes axi status`, or steer the worker with bin/fm-send.sh.",
  "supervisor-poll-in-turn":
    "a supervisor never sleeps or polls inside a turn: the watcher wakes it when something changes. End the turn instead of waiting in it.",
  "supervisor-pane-typing":
    "a secondmate lead steers workers with bin/fm-send.sh and bin/fm-control.sh, never by typing keys into a worker's pane.",
};

// `status` is read-only supervision, so it is deliberately absent.
const OWNED_SUBCOMMANDS = new Set(["run", "respond"]);
const MAX_TURN_SLEEP_SECONDS = 60;
const LOOP_WORDS = new Set(["for", "while", "until"]);
const PANE_TYPING = new Map([
  ["herdr", new Set(["send-text", "send-keys"])],
  ["tmux", new Set(["send-keys"])],
]);

const base = (value) => value.split("/").at(-1);
const argsAfter = (position) => position.words.slice(position.index + 1);

// `no-mistakes --json axi run`: skip leading flags, then an optional `axi`.
function ownsRun(position) {
  const words = argsAfter(position).map((word) => word.value);
  let cursor = 0;
  while (words[cursor]?.startsWith("-")) cursor += 1;
  if (words[cursor] === "axi") cursor += 1;
  return OWNED_SUBCOMMANDS.has(words[cursor]);
}

// Seconds for one sleep argument: `1m30s` is 90, `30` is 30. Undefined when no
// duration is readable, because an unreadable duration cannot be proven short.
function seconds(argument) {
  const units = { s: 1, m: 60, h: 3600, d: 86400 };
  const parts = argument.match(/\d+(?:\.\d+)?[smhd]/g);
  if (parts) {
    return parts.reduce((total, part) => total + Number.parseFloat(part.slice(0, -1)) * units[part.at(-1)], 0);
  }
  return /^\d+(?:\.\d+)?$/.test(argument) ? Number.parseFloat(argument) : undefined;
}

function sleepsTooLong(position) {
  let total = 0;
  for (const word of argsAfter(position)) {
    const amount = seconds(word.value);
    if (amount === undefined) return true;
    total += amount;
  }
  return total > MAX_TURN_SLEEP_SECONDS;
}

// The first rule the command breaks, or null when it is allowed. Malformed shell
// is allowed: this guard's threat is an ordinary, well-formed supervisor drifting.
async function violation(command, { codeRoot, secondmate }) {
  const lexer = await import(url.pathToFileURL(path.join(codeRoot, "bin", "fm-arm-command-policy.mjs")).href);
  const lexed = new lexer.Lexer(command).tokenize();
  if (lexed.error) return null;

  const positions = lexer
    .splitProgram(lexed.tokens)
    .nodes.map((node) => lexer.commandPosition(node))
    .filter((position) => position.command && !position.unresolvedWrapperOption);
  const names = positions.map((position) => base(position.command.value));

  for (const [i, position] of positions.entries()) {
    if (names[i] === "no-mistakes" && ownsRun(position)) return "supervisor-no-mistakes-run";
    const typing = PANE_TYPING.get(names[i]);
    if (secondmate && typing && argsAfter(position).some((word) => typing.has(word.value))) {
      return "supervisor-pane-typing";
    }
  }

  // A loop and its sleep are separate positions, so the loop check is whole-command.
  const inLoop = names.some((name) => LOOP_WORDS.has(name));
  for (const [i, position] of positions.entries()) {
    if (names[i] === "sleep" && sleepsTooLong(position)) return "supervisor-poll-in-turn";
    if (inLoop && position.words.some((word) => base(word.value) === "sleep")) return "supervisor-poll-in-turn";
  }
  return null;
}

function readArgs(argv) {
  const args = { codeRoot: "", command: "", secondmate: false };
  for (let index = 0; index < argv.length; index += 1) {
    const flag = argv[index];
    if (flag === "--secondmate") {
      args.secondmate = true;
    } else if (flag === "--code-root") {
      index += 1;
      args.codeRoot = argv[index] ?? "";
    } else if (flag === "--command") {
      index += 1;
      args.command = argv[index] ?? "";
    } else {
      throw new Error(`unknown argument: ${flag}`);
    }
  }
  if (!args.codeRoot) throw new Error("--code-root is required");
  return args;
}

const args = readArgs(process.argv.slice(2));
const rule = args.command ? await violation(args.command, args) : null;
process.stdout.write(rule ? `deny\t${rule}\t${REASONS[rule]}\n` : "allow\n");
