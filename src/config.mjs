import { readFileSync, existsSync } from "node:fs";
import { resolve } from "node:path";

const DEFAULT_CONFIG = {
  preset: "standard",
  branchPatterns: {
    main: /^(main|master)$/,
    dev: /^(dev|develop)$/,
    feature: /^feature\/[a-z0-9]([a-z0-9-]*[a-z0-9])?$/,
    story: /^story\/[a-z0-9-]+\/[a-z0-9-]+$/,
    release: /^release\/[0-9]+\.[0-9]+\.[0-9]+(-[a-z0-9.]+)?$/,
    hotfix: /^hotfix\/[a-z0-9]([a-z0-9-]*[a-z0-9])?$/,
  },
  hooks: {
    "pre-commit": { enabled: true, source: "branch-guard.sh" },
    "pre-push": { enabled: true, source: "pre-push-gitflow.sh" },
    "post-commit": { enabled: true, source: "post-commit-gitflow.sh" },
    "post-merge": { enabled: true, source: "post-merge-gitflow.sh" },
    "post-checkout": { enabled: true, source: "post-checkout-autopull.sh" },
    "prepare-commit-msg": { enabled: true, source: "prepare-commit-msg-gitflow.sh" },
  },
  strict: false,
  journal: {
    enabled: true,
    dir: "Vault/Gitflow",
    logFile: ".commit-log.jsonl",
  },
  automation: {
    enabled: false,
    url: "http://localhost:9000/api/automation",
    eventPath: "/events",
    triggerPath: "/triage",
    skillCommand: null,
    profile: null,
    profiles: {},
  },
  // Backward-compatible legacy key.
  orchestrator: {
    enabled: false,
    url: "http://localhost:9000/api/automation",
  },
  prePush: {
    driftCheck: { enabled: false, script: null, strict: false },
    customChecks: [],
  },
  preCommit: {
    typecheck: { enabled: false, command: null },
    lint: { enabled: false, command: null },
    customChecks: [],
  },
};

export function loadConfig(repoRoot) {
  const configPath =
    process.env.GITFLOW_GUARD_CONFIG ||
    resolve(repoRoot, ".gitflow-guard.json");

  let userConfig = {};

  if (existsSync(configPath)) {
    try {
      userConfig = JSON.parse(readFileSync(configPath, "utf8"));
    } catch (err) {
      console.warn(`[gitflow-guard] Warning: could not parse ${configPath}: ${err.message}`);
    }
  }

  return deepMerge(DEFAULT_CONFIG, userConfig);
}

function deepMerge(target, source) {
  const result = { ...target };
  for (const key of Object.keys(source)) {
    if (
      source[key] &&
      typeof source[key] === "object" &&
      !Array.isArray(source[key]) &&
      !(source[key] instanceof RegExp)
    ) {
      result[key] = deepMerge(target[key] || {}, source[key]);
    } else {
      result[key] = source[key];
    }
  }
  return result;
}
