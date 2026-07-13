import { spawn } from "node:child_process";
import { existsSync } from "node:fs";
import { readFile } from "node:fs/promises";
import os from "node:os";
import path from "node:path";
import readline from "node:readline";
import { fileURLToPath } from "node:url";

const PLUGIN_ROOT = path.resolve(path.dirname(fileURLToPath(import.meta.url)), "..");
const MANIFEST = JSON.parse(
  await readFile(new URL("../.codex-plugin/plugin.json", import.meta.url), "utf8"),
);
const HOME = os.homedir();
const PYTHON_CANDIDATES = [
  process.env.PYTHON,
  path.join(HOME, ".cache", "codex-runtimes", "codex-primary-runtime", "dependencies", "python", "python.exe"),
  path.join(HOME, "AppData", "Local", "Programs", "Python", "Python312", "python.exe"),
  "python",
  "py",
].filter(Boolean);
const JsonRpcError = {
  METHOD_NOT_FOUND: -32601,
  INVALID_PARAMS: -32602,
  INTERNAL_ERROR: -32603,
};

function send(message) {
  process.stdout.write(`${JSON.stringify(message)}\n`);
}

function sendResult(id, result) {
  send({ jsonrpc: "2.0", id, result });
}

function sendError(id, code, message) {
  send({ jsonrpc: "2.0", id, error: { code, message } });
}

function spawnPython(candidate, args, options) {
  const commandArgs = candidate === "py" ? ["-3", ...args] : args;
  return spawn(candidate, commandArgs, {
    cwd: PLUGIN_ROOT,
    windowsHide: true,
    env: { ...process.env, PYTHONIOENCODING: "utf-8", PYTHONUTF8: "1" },
    ...options,
  });
}

function runPython(args, options = {}) {
  return new Promise((resolve, reject) => {
    const candidates = PYTHON_CANDIDATES.filter(
      (candidate) => !path.isAbsolute(candidate) || existsSync(candidate),
    );
    let index = 0;

    const tryNext = (lastError) => {
      const candidate = candidates[index++];
      if (!candidate) {
        reject(lastError ?? new Error("No Python executable was found."));
        return;
      }

      const child = spawnPython(candidate, args, options);
      let stdout = "";
      let stderr = "";
      child.stdout?.on("data", (chunk) => {
        stdout += chunk.toString();
      });
      child.stderr?.on("data", (chunk) => {
        stderr += chunk.toString();
      });
      child.on("error", (error) => {
        if (error.code === "ENOENT") {
          tryNext(error);
        } else {
          reject(error);
        }
      });
      child.on("close", (code) => {
        if (code === 0) {
          resolve(stdout.trim());
        } else {
          reject(new Error(stderr.trim() || `${candidate} exited with code ${code}`));
        }
      });
    };

    tryNext();
  });
}

function startPythonDetached(args) {
  const candidate = PYTHON_CANDIDATES.find(
    (item) => !path.isAbsolute(item) || existsSync(item),
  );
  if (!candidate) {
    throw new Error("No Python executable was found.");
  }
  const child = spawnPython(candidate, args, { detached: true, stdio: "ignore" });
  child.on("error", () => {});
  child.unref();
  return child;
}

function runPowerShellDetached(args) {
  const child = spawn("powershell.exe", args, {
    cwd: PLUGIN_ROOT,
    detached: true,
    stdio: "ignore",
    windowsHide: true,
    env: process.env,
  });
  child.on("error", () => {});
  child.unref();
  return child;
}

async function collectStatus() {
  const output = await runPython(["./scripts/collect_status.py"]);
  return JSON.parse(output);
}

function summarizeStatus(status) {
  const official = status.officialQuota ?? {};
  const limits = Array.isArray(status.limits) ? status.limits : [];
  const sourceLabels = {
    "official-app-server": "Codex official live data",
    "official-app-server-cache": "Last successful official snapshot",
    manual: "Manual fallback",
  };
  const quotaLines = limits
    .filter((item) => item?.remainingPercent != null)
    .map((item) => {
      const reset = item.resetLabel ? `, ${item.resetLabel}` : "";
      return `${item.label ?? "Codex"}: ${Math.round(item.remainingPercent)}% remaining${reset}.`;
    });
  return [
    `Codex quota status: ${official.status === "available" ? "live" : official.status === "stale" ? "cached" : "unavailable"}.`,
    `Source: ${sourceLabels[official.source] ?? official.source ?? "unknown"}.`,
    ...quotaLines,
    quotaLines.length === 0 ? "No displayable official percentage was returned." : null,
    official.note || null,
  ].filter(Boolean).join("\n");
}

async function handleToolCall(id, params) {
  const name = params?.name;
  const args = params?.arguments ?? {};

  if (name === "codex_quota_status") {
    const status = await collectStatus();
    sendResult(id, {
      content: [{ type: "text", text: summarizeStatus(status) }],
      structuredContent: status,
    });
    return;
  }

  if (name === "codex_quota_render_panel") {
    const output = args.outputPath || path.join(PLUGIN_ROOT, "work", "quota-panel.html");
    const result = await runPython(["./scripts/render_panel.py", "--output", output]);
    const payload = JSON.parse(result);
    sendResult(id, {
      content: [{ type: "text", text: `Rendered Codex quota panel: ${payload.output}` }],
      structuredContent: payload,
    });
    return;
  }

  if (name === "codex_quota_start_panel") {
    const port = Number.isInteger(args.port) ? args.port : 17447;
    const host = "127.0.0.1";
    startPythonDetached(["./scripts/panel_server.py", "--port", String(port)]);
    const url = `http://${host}:${port}/`;
    sendResult(id, {
      content: [{ type: "text", text: `Started Codex quota panel: ${url}` }],
      structuredContent: { url, host, port },
    });
    return;
  }

  if (name === "codex_quota_start_float") {
    runPowerShellDetached([
      "-NoProfile",
      "-ExecutionPolicy",
      "Bypass",
      "-File",
      path.join(PLUGIN_ROOT, "scripts", "start_float.ps1"),
    ]);
    sendResult(id, {
      content: [{
        type: "text",
        text: "Started Codex Quota Float. Click to expand, drag to move, double-click for details, or right-click for the menu.",
      }],
      structuredContent: { status: "started" },
    });
    return;
  }

  if (name === "codex_quota_stop_float") {
    runPowerShellDetached([
      "-NoProfile",
      "-ExecutionPolicy",
      "Bypass",
      "-File",
      path.join(PLUGIN_ROOT, "scripts", "stop_float.ps1"),
    ]);
    sendResult(id, {
      content: [{ type: "text", text: "Stopped the Codex Quota Float widget if it was running." }],
      structuredContent: { status: "stopped" },
    });
    return;
  }

  sendError(id, JsonRpcError.INVALID_PARAMS, `Unknown tool: ${name ?? ""}`);
}

async function handleRequest(message) {
  const { id, method, params } = message;

  if (method === "initialize") {
    sendResult(id, {
      protocolVersion: params?.protocolVersion ?? "2025-11-25",
      capabilities: { tools: {} },
      serverInfo: { name: "Codex Quota Float", version: MANIFEST.version },
      instructions: "Use these tools for official Codex quota and reset times. The plugin does not read authentication files, task titles, or conversation content. Clearly label cached fallback values.",
    });
    return;
  }

  if (method === "ping") {
    sendResult(id, {});
    return;
  }

  if (method === "tools/list") {
    sendResult(id, {
      tools: [
        {
          name: "codex_quota_status",
          title: "Check Codex Quota Status",
          description: "Read official Codex remaining percentages and reset times through account/rateLimits/read. Does not read auth.json and clearly labels cached values.",
          inputSchema: { type: "object", properties: {}, additionalProperties: false },
          annotations: { readOnlyHint: true, destructiveHint: false, idempotentHint: true, openWorldHint: false },
        },
        {
          name: "codex_quota_render_panel",
          title: "Render Codex Quota Panel",
          description: "Render a standalone HTML panel using the latest official Codex quota snapshot.",
          inputSchema: {
            type: "object",
            properties: {
              outputPath: { type: "string", description: "Optional absolute output path for the HTML panel." },
            },
            additionalProperties: false,
          },
          annotations: { readOnlyHint: false, destructiveHint: false, idempotentHint: true, openWorldHint: false },
        },
        {
          name: "codex_quota_start_panel",
          title: "Start Codex Quota Panel",
          description: "Start a loopback-only panel at http://127.0.0.1:17447/ using official Codex quota snapshots.",
          inputSchema: {
            type: "object",
            properties: {
              port: { type: "integer", minimum: 1024, maximum: 65535, description: "Port to bind. Defaults to 17447." },
            },
            additionalProperties: false,
          },
          annotations: { readOnlyHint: false, destructiveHint: false, idempotentHint: false, openWorldHint: false },
        },
        {
          name: "codex_quota_start_float",
          title: "Start Codex Quota Float Widget",
          description: "Start the always-on-top Windows widget with official remaining percentages, quota periods, and reset times. It refreshes silently about once per minute.",
          inputSchema: { type: "object", properties: {}, additionalProperties: false },
          annotations: { readOnlyHint: false, destructiveHint: false, idempotentHint: false, openWorldHint: false },
        },
        {
          name: "codex_quota_stop_float",
          title: "Stop Codex Quota Float Widget",
          description: "Stop the desktop quota widget if it is running.",
          inputSchema: { type: "object", properties: {}, additionalProperties: false },
          annotations: { readOnlyHint: false, destructiveHint: false, idempotentHint: true, openWorldHint: false },
        },
      ],
    });
    return;
  }

  if (method === "tools/call") {
    try {
      await handleToolCall(id, params);
    } catch (error) {
      sendError(id, JsonRpcError.INTERNAL_ERROR, error instanceof Error ? error.message : String(error));
    }
    return;
  }

  if (id !== undefined) {
    sendError(id, JsonRpcError.METHOD_NOT_FOUND, `Method not found: ${method}`);
  }
}

const lines = readline.createInterface({ input: process.stdin, crlfDelay: Infinity });
lines.on("line", (line) => {
  if (!line.trim()) {
    return;
  }
  try {
    void handleRequest(JSON.parse(line));
  } catch {
    // Ignore malformed input; JSON-RPC clients send one request per line.
  }
});
