import { HttpAgent } from "@icp-sdk/core/agent";
import { safeGetCanisterEnv } from "@icp-sdk/core/agent/canister-env";
import { createActor } from "../backend/api/backend";
import type { Backend } from "../backend/api/backend";

const canisterEnv = safeGetCanisterEnv();
const BACKEND_CANISTER_ID = canisterEnv?.["PUBLIC_CANISTER_ID:backend"] ?? "";

export async function getActor(identity: unknown): Promise<Backend> {
  const agent = await HttpAgent.create({
    // Cross-package Identity type — compatible at runtime, cast needed for TS
    // eslint-disable-next-line @typescript-eslint/no-explicit-any
    identity: identity as any,
    host: window.location.origin,
    // IC_ROOT_KEY from ic_env cookie (set by Vite dev server or asset canister)
    // Never call fetchRootKey() — see II skill pitfall #4
    // eslint-disable-next-line @typescript-eslint/no-explicit-any
    rootKey: (canisterEnv as any)?.IC_ROOT_KEY,
  });
  return createActor(BACKEND_CANISTER_ID, { agent });
}
