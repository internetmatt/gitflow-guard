#!/usr/bin/env node
/**
 * gitflow-guard CLI
 *
 * Commands:
 *   init            Install git hooks into the current repo
 *   remove          Uninstall gitflow-guard hooks
 *   status          Show hook installation status
 *   check-branch    Validate current branch name against policy
 *   check-push      Validate a push against GitFlow merge rules
 *   run-hook <name> Execute a specific hook directly
 */
import { resolve, dirname } from "node:path";
import { fileURLToPath } from "node:url";
import { existsSync } from "node:fs";
import { execSync, spawnSync } from "node:child_process";
import {
  installHooks,
  uninstallHooks,
  statusHooks,
} from "../src/installer.mjs";
import { loadConfig } from "../src/config.mjs";

const __dirname = dirname(fileURLToPath(import.meta.url));
const VERSION = "1.0.0";

const args = process.argv.slice(2);
const command = args[0];

function usage() {
  console.log(`
gitflow-guard v${VERSION}

Usage:
  gitflow-guard init [--preset <name>]   Install hooks (presets: standard, projects, minimal)
  gitflow-guard init --sparse <cone,...>  Sparse-checkout a repo and install hooks scoped to cone
  gitflow-guard remove                   Uninstall hooks
  gitflow-guard status                   Show installation status
  gitflow-guard check-branch             Validate current branch name
  gitflow-guard check-push               Validate push against GitFlow rules
  gitflow-guard run-hook <hook-name>     Execute a hook script directly
  gitflow-guard setup-worktree <path> [--cone <dirs>]  Create agent worktree with sparse cone
  gitflow-guard --version                Print version

Environment:
  GITFLOW_STRICT=1                       Block commits on invalid branch names
  GITFLOW_GUARD_CONFIG=<path>            Path to config file (default: .gitflow-guard.json)
`);
}

function repoRoot() {
  try {
    return execSync("git rev-parse --show-toplevel", { encoding: "utf8" }).trim();
  } catch {
    console.error("[gitflow-guard] Not inside a git repository.");
    process.exit(1);
  }
}

async function main() {
  if (!command || command === "--help" || command === "-h") {
    usage();
    process.exit(0);
  }

  if (command === "--version" || command === "-v") {
    console.log(VERSION);
    process.exit(0);
  }

  const root = repoRoot();
  const config = loadConfig(root);

  switch (command) {
    case "init": {
      const presetFlag = args.indexOf("--preset");
      const preset = presetFlag >= 0 ? args[presetFlag + 1] : config.preset || "standard";
      const sparseFlag = args.indexOf("--sparse");
      if (sparseFlag >= 0) {
        const cone = args[sparseFlag + 1];
        if (!cone) {
          console.error("[gitflow-guard] --sparse requires a comma-separated list of cone directories");
          process.exit(1);
        }
        const { setupSparseCheckout } = await import("../src/sparse.mjs");
        setupSparseCheckout(root, cone.split(","));
      }
      installHooks(root, preset, config);
      break;
    }
    case "setup-worktree": {
      const wtPath = args[1];
      if (!wtPath) {
        console.error("[gitflow-guard] Missing worktree path. Usage: gitflow-guard setup-worktree <path> [--cone <dirs>]");
        process.exit(1);
      }
      const coneFlag = args.indexOf("--cone");
      const coneDirs = coneFlag >= 0 ? args[coneFlag + 1]?.split(",") : [];
      const presetForWt = args.includes("--preset") ? args[args.indexOf("--preset") + 1] : config.preset || "standard";
      const { createAgentWorktree } = await import("../src/sparse.mjs");
      createAgentWorktree(root, wtPath, coneDirs, presetForWt, config);
      break;
    }
    case "remove":
      uninstallHooks(root);
      break;
    case "status":
      statusHooks(root, config);
      break;
    case "check-branch": {
      const hookPath = resolve(__dirname, "..", "hooks", "branch-guard.sh");
      const result = spawnSync("bash", [hookPath], {
        cwd: root,
        stdio: "inherit",
        env: { ...process.env, GITFLOW_GUARD_ROOT: root },
      });
      process.exit(result.status ?? 1);
    }
    case "check-push": {
      const hookPath = resolve(__dirname, "..", "hooks", "pre-push-gitflow.sh");
      const remote = args[1] || "origin";
      const url = args[2] || "";
      const result = spawnSync("bash", [hookPath, remote, url], {
        cwd: root,
        stdio: "inherit",
        env: { ...process.env, GITFLOW_GUARD_ROOT: root },
      });
      process.exit(result.status ?? 1);
    }
    case "run-hook": {
      const hookName = args[1];
      if (!hookName) {
        console.error("[gitflow-guard] Missing hook name. Usage: gitflow-guard run-hook <name>");
        process.exit(1);
      }
      const hookMapping = {
        "prepare-commit-msg": "prepare-commit-msg-gitflow.sh",
        "post-commit": "post-commit-gitflow.sh",
        "post-merge": "post-merge-gitflow.sh",
        "post-checkout": "post-checkout-autopull.sh",
        "pre-push": "pre-push-gitflow.sh",
        "pre-commit": "branch-guard.sh",
      };
      const scriptName = hookMapping[hookName] || `${hookName}.sh`;
      const hookPath = resolve(__dirname, "..", "hooks", scriptName);
      if (!existsSync(hookPath)) {
        console.error(`[gitflow-guard] Hook not found: ${hookName} (looked for ${scriptName})`);
        process.exit(1);
      }
      const result = spawnSync("bash", [hookPath, ...args.slice(2)], {
        cwd: root,
        stdio: "inherit",
        env: { ...process.env, GITFLOW_GUARD_ROOT: root },
      });
      process.exit(result.status ?? 1);
    }
    default:
      console.error(`[gitflow-guard] Unknown command: ${command}`);
      usage();
      process.exit(1);
  }
}

main();
