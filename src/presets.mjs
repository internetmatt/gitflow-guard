import { readFileSync, existsSync, readdirSync } from "node:fs";
import { resolve, dirname } from "node:path";
import { fileURLToPath } from "node:url";

const __dirname = dirname(fileURLToPath(import.meta.url));
const PRESETS_DIR = resolve(__dirname, "..", "presets");

const BUILTIN_PRESETS = {
  standard: {
    preset: "standard",
    strict: false,
    hooks: {
      "pre-commit": { enabled: true, source: "branch-guard.sh" },
      "pre-push": { enabled: true, source: "pre-push-gitflow.sh" },
      "post-commit": { enabled: true, source: "post-commit-gitflow.sh" },
      "post-merge": { enabled: true, source: "post-merge-gitflow.sh" },
      "post-checkout": { enabled: true, source: "post-checkout-autopull.sh" },
      "prepare-commit-msg": { enabled: true, source: "prepare-commit-msg-gitflow.sh" },
    },
    branchPatterns: {
      allowed: ["main", "dev", "feature/*", "story/*", "release/*", "hotfix/*"],
    },
    journal: {
      enabled: true,
      dir: "Vault/Gitflow",
      logFile: ".commit-log.jsonl",
    },
    automation: {
      enabled: true,
      url: "http://localhost:9000/api/automation",
      eventPath: "/events",
      triggerPath: "/triage",
      skillCommand: null,
    },
    prePush: {
      driftCheck: { enabled: false, script: null, strict: false },
    },
    preCommit: {
      typecheck: { enabled: false },
      lint: { enabled: false },
      sqlBoundaryCheck: { enabled: true },
    },
  },

  projects: {
    preset: "projects",
    strict: false,
    hooks: {
      "pre-commit": { enabled: true, source: "branch-guard.sh" },
      "pre-push": { enabled: true, source: "pre-push-gitflow.sh" },
      "post-commit": { enabled: true, source: "post-commit-gitflow.sh" },
      "post-merge": { enabled: true, source: "post-merge-gitflow.sh" },
      "post-checkout": { enabled: true, source: "post-checkout-autopull.sh" },
      "prepare-commit-msg": { enabled: true, source: "prepare-commit-msg-gitflow.sh" },
    },
    branchPatterns: {
      allowed: ["main", "dev", "feature/*", "story/*", "release/*", "hotfix/*"],
    },
    journal: {
      enabled: true,
      dir: "Vault/Gitflow",
      logFile: ".commit-log.jsonl",
    },
    automation: {
      enabled: true,
      url: "http://localhost:9000/api/automation",
      eventPath: "/events",
      triggerPath: "/triage",
      skillCommand: null,
    },
    preCommit: {
      typecheck: {
        enabled: true,
        command: "NX_DAEMON=false pnpm exec nx run-many --targets=typecheck --parallel=1",
      },
      lint: {
        enabled: true,
        command: "pnpm exec eslint --max-warnings 0",
        stagedOnly: true,
        extensions: [".ts", ".tsx", ".js", ".jsx"],
      },
    },
    containerMode: {
      enabled: true,
      automationPort: 9000,
      dualMode: true,
    },
  },

  minimal: {
    preset: "minimal",
    strict: false,
    hooks: {
      "pre-commit": { enabled: true, source: "branch-guard.sh" },
      "pre-push": { enabled: true, source: "pre-push-gitflow.sh" },
      "post-commit": { enabled: false },
      "post-merge": { enabled: false },
      "post-checkout": { enabled: false },
      "prepare-commit-msg": { enabled: false },
    },
    branchPatterns: {
      allowed: ["main", "dev", "feature/*", "release/*", "hotfix/*"],
    },
    journal: { enabled: false },
    automation: { enabled: false },
  },
};

// Legacy alias kept for backward compatibility with existing configs/scripts.
BUILTIN_PRESETS.projecto = {
  ...BUILTIN_PRESETS.standard,
  preset: "projecto",
};

export function loadPreset(name) {
  if (BUILTIN_PRESETS[name]) {
    return BUILTIN_PRESETS[name];
  }

  const filePath = resolve(PRESETS_DIR, `${name}.json`);
  if (existsSync(filePath)) {
    return JSON.parse(readFileSync(filePath, "utf8"));
  }

  console.warn(`[gitflow-guard] Unknown preset "${name}", falling back to "standard".`);
  return BUILTIN_PRESETS.standard;
}

export function listPresets() {
  const names = Object.keys(BUILTIN_PRESETS);
  if (existsSync(PRESETS_DIR)) {
    for (const f of readdirSync(PRESETS_DIR)) {
      if (f.endsWith(".json")) names.push(f.replace(".json", ""));
    }
  }
  return [...new Set(names)];
}
