import { execFileSync, execSync } from "node:child_process";
import { existsSync } from "node:fs";
import { resolve } from "node:path";
import { installHooks } from "./installer.mjs";
import { loadConfig } from "./config.mjs";
import { loadPreset } from "./presets.mjs";

/**
 * Enable sparse checkout on the current repo and set the cone.
 * Hooks installed afterward will be cone-aware: lint/typecheck
 * only runs against staged files within the sparse cone.
 */
export function setupSparseCheckout(repoRoot, coneDirs) {
  console.log(`[gitflow-guard] Setting up sparse checkout...`);

  try {
    execSync("git sparse-checkout init --cone", { cwd: repoRoot, stdio: "inherit" });
  } catch {
    console.warn("[gitflow-guard] sparse-checkout init failed (may already be enabled)");
  }

  if (coneDirs.length > 0) {
    execFileSync("git", ["sparse-checkout", "set", ...coneDirs], { cwd: repoRoot, stdio: "inherit" });
    console.log(`[gitflow-guard] Sparse cone set to: ${coneDirs.join(", ")}`);
  }
}

/**
 * Create a git worktree with optional sparse checkout for agent isolation.
 *
 * Agents (Copilot, Claude, Codex) get their own worktree with:
 *  - A sparse cone scoped to only the directories they need
 *  - gitflow-guard hooks installed in that worktree's .git
 *  - Hooks that are cone-aware (only check files within the cone)
 *
 * Usage:
 *   gitflow-guard setup-worktree /tmp/agent-work --cone apps,libs,packages --preset standard
 */
export function createAgentWorktree(repoRoot, worktreePath, coneDirs, presetName, config) {
  const absPath = resolve(worktreePath);

  console.log(`[gitflow-guard] Creating agent worktree at ${absPath}...`);

  // Determine branch — use current branch or create a detached one
  let branch;
  try {
    branch = execSync("git symbolic-ref --short HEAD", { cwd: repoRoot, encoding: "utf8" }).trim();
  } catch {
    branch = "HEAD";
  }

  // Create worktree
  if (existsSync(absPath)) {
    console.log(`[gitflow-guard] Worktree path already exists, using existing.`);
  } else {
    try {
      execFileSync("git", ["worktree", "add", "--detach", "--", absPath], { cwd: repoRoot, stdio: "inherit" });
    } catch (err) {
      console.error(`[gitflow-guard] Failed to create worktree: ${err.message}`);
      process.exit(1);
    }
  }

  // Enable sparse checkout in the worktree
  if (coneDirs && coneDirs.length > 0 && coneDirs[0] !== "") {
    try {
      execSync("git sparse-checkout init --cone", { cwd: absPath, stdio: "inherit" });
      execFileSync("git", ["sparse-checkout", "set", ...coneDirs], { cwd: absPath, stdio: "inherit" });
      console.log(`[gitflow-guard] Sparse cone: ${coneDirs.join(", ")}`);
    } catch (err) {
      console.warn(`[gitflow-guard] Sparse checkout setup warning: ${err.message}`);
    }
  }

  // Install hooks in the worktree
  const wtConfig = loadConfig(absPath);
  const preset = loadPreset(presetName);
  const mergedConfig = { ...config, ...wtConfig, ...preset };
  installHooks(absPath, presetName, mergedConfig);

  console.log(`\n[gitflow-guard] Agent worktree ready at ${absPath}`);
  console.log(`[gitflow-guard] Hooks are scoped to sparse cone — only cone files are checked.`);
}
