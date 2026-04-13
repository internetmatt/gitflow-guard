import { readFileSync, writeFileSync, existsSync, mkdirSync, unlinkSync, chmodSync } from "node:fs";
import { resolve, dirname } from "node:path";
import { fileURLToPath } from "node:url";
import { execSync } from "node:child_process";
import { loadPreset } from "./presets.mjs";

const __dirname = dirname(fileURLToPath(import.meta.url));
const HOOKS_DIR = resolve(__dirname, "..", "hooks");
const MARKER = "# gitflow-guard-hook";

const HOOK_NAMES = [
  "prepare-commit-msg",
  "post-commit",
  "post-merge",
  "post-checkout",
  "pre-push",
  "pre-commit",
];

function resolveGitDir(repoPath) {
  const dotGit = resolve(repoPath, ".git");
  if (!existsSync(dotGit)) return null;

  try {
    const stat = readFileSync(dotGit, "utf8").trim();
    if (stat.startsWith("gitdir: ")) {
      const gitdir = stat.slice(8);
      return gitdir.startsWith("/") ? gitdir : resolve(repoPath, gitdir);
    }
  } catch {
    // .git is a directory, not a file
  }
  return dotGit;
}

function hookSourcePath(hookName) {
  const mapping = {
    "prepare-commit-msg": "prepare-commit-msg-gitflow.sh",
    "post-commit": "post-commit-gitflow.sh",
    "post-merge": "post-merge-gitflow.sh",
    "post-checkout": "post-checkout-autopull.sh",
    "pre-push": "pre-push-gitflow.sh",
    "pre-commit": "branch-guard.sh",
  };
  return resolve(HOOKS_DIR, mapping[hookName] || `${hookName}.sh`);
}

function removeManagedBlock(content, marker) {
  const markerEnd = `${marker}-end`;
  const lines = content.split("\n");
  const filtered = [];
  let inBlock = false;

  for (const line of lines) {
    if (line.includes(marker) && !line.includes(markerEnd)) {
      inBlock = true;
      continue;
    }
    if (line.includes(markerEnd)) {
      inBlock = false;
      continue;
    }
    if (!inBlock) filtered.push(line);
  }

  return filtered.join("\n").replace(/\n+$/, "\n");
}

function insertBlockFirst(content, block) {
  const lines = content.split("\n");
  if (lines[0]?.startsWith("#!")) {
    return `${lines[0]}\n\n${block}\n${lines.slice(1).join("\n")}`.replace(/\n+$/, "\n");
  }
  return `#!/usr/bin/env bash\n\n${block}\n${content}`.replace(/\n+$/, "\n");
}

function installHook(gitDir, hookName, config) {
  const hooksDir = resolve(gitDir, "hooks");
  mkdirSync(hooksDir, { recursive: true });

  const target = resolve(hooksDir, hookName);
  const source = hookSourcePath(hookName);
  const marker = `${MARKER}:${hookName}`;

  if (!existsSync(source)) {
    console.warn(`  [skip] Hook source not found: ${source}`);
    return;
  }

  // pre-commit and pre-push must propagate exit codes to block pushes/commits
  const blockingHooks = new Set(["pre-commit", "pre-push"]);
  const errorHandler = blockingHooks.has(hookName) ? "" : "|| true";
  const sourceBasename = source.split("/").pop();

  const block = `
${marker} — DO NOT EDIT THIS BLOCK
_gfg_root="\${GITFLOW_GUARD_ROOT:-\$(git rev-parse --show-toplevel 2>/dev/null)}"
_gfg_hooks=""
if [ -f "\${_gfg_root}/.gitflow-guard.json" ]; then
  _gfg_hooks=\$(grep -o '"hooksPath"[[:space:]]*:[[:space:]]*"[^"]*"' "\${_gfg_root}/.gitflow-guard.json" 2>/dev/null | head -1 | sed 's/.*"\\([^"]*\\)"$/\\1/')
fi
_gfg_script="\${_gfg_hooks:-${HOOKS_DIR}}/${sourceBasename}"
if [ -x "\$_gfg_script" ] || [ -f "\$_gfg_script" ]; then
  GITFLOW_GUARD_ROOT="\$_gfg_root" bash "\$_gfg_script" "$@" ${errorHandler}
fi
${marker}-end`;

  if (existsSync(target)) {
    const existing = readFileSync(target, "utf8");
    const hasMarker = existing.includes(marker);

    if (hasMarker) {
      const sanitized = removeManagedBlock(existing, marker);
      const reordered = insertBlockFirst(sanitized, block);
      if (existing !== reordered) {
        writeFileSync(target, reordered);
        console.log(`  [reorder] Moved to first: ${hookName}`);
      } else {
        console.log(`  [ok] Already installed first: ${hookName}`);
      }
      return;
    }

    const chained = insertBlockFirst(existing, block);
    writeFileSync(target, chained);
    console.log(`  [chain] Installed first, chained existing: ${hookName}`);
  } else {
    writeFileSync(target, `#!/usr/bin/env bash\n${block}\n`);
    chmodSync(target, 0o755);
    console.log(`  [new] Installed: ${hookName}`);
  }
}

function uninstallHook(gitDir, hookName) {
  const target = resolve(gitDir, "hooks", hookName);
  const marker = `${MARKER}:${hookName}`;

  if (!existsSync(target)) {
    console.log(`  [skip] Not installed: ${hookName}`);
    return;
  }

  const content = readFileSync(target, "utf8");
  if (!content.includes(marker)) {
    console.log(`  [skip] Not our hook: ${hookName}`);
    return;
  }

  const filtered = removeManagedBlock(content, marker).split("\n");

  const remaining = filtered.filter((l) => !/^(#!\/|$)/.test(l.trim())).join("").trim();
  if (!remaining) {
    unlinkSync(target);
    console.log(`  [removed] ${hookName}`);
  } else {
    writeFileSync(target, filtered.join("\n") + "\n");
    console.log(`  [cleaned] Removed our block, kept existing: ${hookName}`);
  }
}

function checkHook(gitDir, hookName) {
  const target = resolve(gitDir, "hooks", hookName);
  const marker = `${MARKER}:${hookName}`;
  if (existsSync(target) && readFileSync(target, "utf8").includes(marker)) {
    return true;
  }
  return false;
}

export function installHooks(repoRoot, presetName, config) {
  const gitDir = resolveGitDir(repoRoot);
  if (!gitDir) {
    console.error("[gitflow-guard] No .git directory found.");
    process.exit(1);
  }

  const preset = loadPreset(presetName);
  console.log(`[gitflow-guard] Installing hooks (preset: ${presetName})...`);

  const configPath = resolve(repoRoot, ".gitflow-guard.json");
  if (!existsSync(configPath)) {
    const configWithPaths = { ...preset, hooksPath: HOOKS_DIR };
    writeFileSync(configPath, JSON.stringify(configWithPaths, null, 2) + "\n");
    console.log(`  [config] Created .gitflow-guard.json`);
  } else {
    const existing = JSON.parse(readFileSync(configPath, "utf8"));
    if (existing.hooksPath !== HOOKS_DIR) {
      existing.hooksPath = HOOKS_DIR;
      writeFileSync(configPath, JSON.stringify(existing, null, 2) + "\n");
      console.log(`  [config] Updated hooksPath in .gitflow-guard.json`);
    }
  }

  const enabledHooks = preset.hooks || config.hooks;
  for (const hookName of HOOK_NAMES) {
    const hookConfig = enabledHooks[hookName];
    if (hookConfig && hookConfig.enabled !== false) {
      installHook(gitDir, hookName, config);
    } else {
      console.log(`  [skip] Disabled: ${hookName}`);
    }
  }

  // Install into submodules if present
  const gitmodulesPath = resolve(repoRoot, ".gitmodules");
  if (existsSync(gitmodulesPath)) {
    try {
      const submodules = execSync("git submodule foreach --quiet 'echo $sm_path'", {
        cwd: repoRoot,
        encoding: "utf8",
      }).trim().split("\n").filter(Boolean);

      for (const sm of submodules) {
        const smRoot = resolve(repoRoot, sm);
        const smGitDir = resolveGitDir(smRoot);
        if (smGitDir) {
          console.log(`\n  [submodule: ${sm}]`);
          for (const hookName of HOOK_NAMES) {
            const hookConfig = enabledHooks[hookName];
            if (hookConfig && hookConfig.enabled !== false) {
              installHook(smGitDir, hookName, config);
            }
          }
        }
      }
    } catch {
      console.warn("  [warn] Could not enumerate submodules.");
    }
  }

  console.log("\n[gitflow-guard] Done.");
}

export function uninstallHooks(repoRoot) {
  const gitDir = resolveGitDir(repoRoot);
  if (!gitDir) {
    console.error("[gitflow-guard] No .git directory found.");
    process.exit(1);
  }

  console.log("[gitflow-guard] Removing hooks...");
  for (const hookName of HOOK_NAMES) {
    uninstallHook(gitDir, hookName);
  }
  console.log("\n[gitflow-guard] Done.");
}

export function statusHooks(repoRoot, config) {
  const gitDir = resolveGitDir(repoRoot);
  if (!gitDir) {
    console.error("[gitflow-guard] No .git directory found.");
    process.exit(1);
  }

  console.log("[gitflow-guard] Hook status:");
  for (const hookName of HOOK_NAMES) {
    const installed = checkHook(gitDir, hookName);
    const symbol = installed ? "✓" : "✗";
    console.log(`  ${symbol} ${hookName}`);
  }

  const configPath = resolve(repoRoot, ".gitflow-guard.json");
  console.log(`\n  Config: ${existsSync(configPath) ? configPath : "none (using defaults)"}`);

  const journalDir = resolve(repoRoot, config?.journal?.dir || "Vault/Gitflow");
  const logPath = resolve(journalDir, config?.journal?.logFile || ".commit-log.jsonl");
  if (existsSync(logPath)) {
    const lines = readFileSync(logPath, "utf8").trim().split("\n").length;
    console.log(`  Journal: ${lines} entries in ${logPath}`);
  } else {
    console.log("  Journal: no entries yet");
  }
}
