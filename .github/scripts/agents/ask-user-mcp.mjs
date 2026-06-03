#!/usr/bin/env node
// ask-user-mcp.mjs
//
// A minimal, zero-dependency stdio MCP server exposing a single `ask_user` tool.
// The Maestro Blueprint agent runs non-interactively under `claude -p`, so it cannot
// use AskUserQuestion. This tool lets it surface clarifying questions and block until
// the human answers on the controlling terminal.
//
// Protocol: newline-delimited JSON-RPC 2.0 over stdin/stdout (MCP stdio transport).
//   - stdout carries ONLY protocol messages. Writing anything else corrupts the stream.
//   - All human-facing I/O goes to /dev/tty (survives the pipe/tee redirection upstream).
//   - Debug/errors go to stderr (which lands in the maestro log).

import { createReadStream, createWriteStream } from "node:fs";
import { createInterface } from "node:readline";

const PROTOCOL_VERSION = "2024-11-05";
const SERVER_INFO = { name: "maestro-ask-user", version: "1.0.0" };

const TOOL = {
  name: "ask_user",
  description:
    "Ask the human one or more clarifying questions about the feature request and block " +
    "until they answer. Use ONLY for load-bearing facts you cannot resolve from the repo " +
    "(deployment target, external integration contract, behavior of an existing system). " +
    "Do NOT ask about taste or aesthetics. Batch all questions into a single call.",
  inputSchema: {
    type: "object",
    properties: {
      questions: {
        type: "array",
        items: { type: "string" },
        minItems: 1,
        description: "The clarifying questions to ask, each as a separate string.",
      },
      context: {
        type: "string",
        description: "Optional one-line preface explaining why you are asking.",
      },
    },
    required: ["questions"],
  },
};

function send(message) {
  process.stdout.write(`${JSON.stringify(message)}\n`);
}

function reply(id, result) {
  send({ jsonrpc: "2.0", id, result });
}

function replyError(id, code, message) {
  send({ jsonrpc: "2.0", id, error: { code, message } });
}

// Drive the controlling terminal directly. Returns a Q/A transcript string, or throws
// if /dev/tty is unavailable (e.g. no controlling terminal).
function askOnTty({ questions, context }) {
  return new Promise((resolve, reject) => {
    let input;
    let output;
    try {
      input = createReadStream("/dev/tty");
      output = createWriteStream("/dev/tty");
    } catch (err) {
      reject(err);
      return;
    }
    input.on("error", reject);
    output.on("error", reject);

    const rl = createInterface({ input, output, terminal: true });
    const transcript = [];

    output.write("\n━━━ Maestro Blueprint needs your input ━━━\n");
    if (context?.trim()) {
      output.write(`${context.trim()}\n`);
    }
    output.write("\n");

    let i = 0;
    const next = () => {
      if (i >= questions.length) {
        rl.close();
        input.destroy();
        output.end();
        resolve(transcript.map((qa) => `Q: ${qa.q}\nA: ${qa.a}`).join("\n\n") || "(no answers)");
        return;
      }
      const q = questions[i];
      const label = questions.length > 1 ? `[${i + 1}/${questions.length}] ` : "";
      rl.question(`${label}${q}\n> `, (answer) => {
        transcript.push({ q, a: answer.trim() || "(no answer)" });
        i += 1;
        next();
      });
    };
    next();
  });
}

async function handleToolCall(id, params) {
  if (!params || params.name !== TOOL.name) {
    replyError(id, -32602, `Unknown tool: ${params?.name}`);
    return;
  }
  const args = params.arguments ?? {};
  const questions = Array.isArray(args.questions)
    ? args.questions.filter((q) => typeof q === "string" && q.trim())
    : [];
  if (questions.length === 0) {
    reply(id, {
      content: [{ type: "text", text: "No questions provided." }],
      isError: true,
    });
    return;
  }

  try {
    const text = await askOnTty({ questions, context: args.context });
    reply(id, { content: [{ type: "text", text }] });
  } catch (err) {
    // No terminal available — tell the agent to proceed on its own rather than block.
    reply(id, {
      content: [
        {
          type: "text",
          text:
            "Could not reach the human (no interactive terminal available). " +
            "Proceed using your best judgement without waiting for an answer.",
        },
      ],
      isError: true,
    });
    process.stderr.write(`[ask-user-mcp] tty unavailable: ${err?.message}\n`);
  }
}

function handleMessage(msg) {
  // Notifications have no id and require no response.
  if (msg.id === undefined || msg.id === null) {
    return;
  }
  switch (msg.method) {
    case "initialize":
      reply(msg.id, {
        protocolVersion: PROTOCOL_VERSION,
        capabilities: { tools: {} },
        serverInfo: SERVER_INFO,
      });
      return;
    case "ping":
      reply(msg.id, {});
      return;
    case "tools/list":
      reply(msg.id, { tools: [TOOL] });
      return;
    case "tools/call":
      handleToolCall(msg.id, msg.params);
      return;
    default:
      replyError(msg.id, -32601, `Method not found: ${msg.method}`);
  }
}

const rl = createInterface({ input: process.stdin });
rl.on("line", (line) => {
  const trimmed = line.trim();
  if (!trimmed) {
    return;
  }
  let msg;
  try {
    msg = JSON.parse(trimmed);
  } catch (err) {
    process.stderr.write(`[ask-user-mcp] bad JSON: ${err?.message}\n`);
    return;
  }
  handleMessage(msg);
});
