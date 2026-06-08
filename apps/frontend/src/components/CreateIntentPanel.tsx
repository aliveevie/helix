import { buildIntent, intentDigest, signIntent } from "@helix/sdk";
import { useState } from "react";
import type { Account, Address, Hex, WalletClient } from "viem";
import { useAccount, useWalletClient } from "wagmi";
import { ADDRESSES, DEMO_POOLS, TARGET_CHAIN_ID } from "../config";
import { safeStringify, short } from "../lib/format";
import { useStore } from "../lib/store";
import type { SignedIntent } from "../lib/types";
import { Card, Field, Notice } from "./ui";

const DEFAULT_DEADLINE_OFFSET = 3600; // 1h

function nowSec() {
  return Math.floor(Date.now() / 1000);
}

/** A deterministic synthetic signature for mock mode (clearly not a real sig). */
function mockSignature(digest: Hex): Hex {
  const body = digest.slice(2).padEnd(128, "0").slice(0, 128);
  return `0xdead${body}1b` as Hex;
}

const MOCK_LP = "0x00000000000000000000000000000000000000A1" as Address;

export function CreateIntentPanel() {
  const { address, isConnected } = useAccount();
  const { data: walletClient } = useWalletClient();
  const store = useStore();

  const [pool, setPool] = useState<Hex>(DEMO_POOLS[0]!.id);
  const [maxDriftBps, setMaxDriftBps] = useState("250");
  const [minDuration, setMinDuration] = useState("3600");
  const [maxSize, setMaxSize] = useState("100");
  const [repFloor, setRepFloor] = useState("0");
  const [nonce, setNonce] = useState(() => String(nowSec()));
  const [deadline, setDeadline] = useState(() => String(nowSec() + DEFAULT_DEADLINE_OFFSET));

  const [busy, setBusy] = useState(false);
  const [error, setError] = useState<string | null>(null);
  const [result, setResult] = useState<SignedIntent | null>(null);

  const lp = (address as Address | undefined) ?? MOCK_LP;
  const live = isConnected && Boolean(walletClient);

  async function onSubmit(e: React.FormEvent) {
    e.preventDefault();
    setError(null);
    setBusy(true);
    setResult(null);
    try {
      // maxSize entered as a whole-token amount → scale to 1e18 (uint128).
      const maxSizeWad = BigInt(Math.round(Number(maxSize) * 1e6)) * 10n ** 12n;

      const intent = buildIntent({
        lp,
        pool,
        maxDriftBps: BigInt(maxDriftBps || "0"),
        minDuration: BigInt(minDuration || "0"),
        maxSize: maxSizeWad,
        repFloor: Number(repFloor || "0"),
        nonce: BigInt(nonce || "0"),
        deadline: BigInt(deadline || "0"),
      });

      const digest = intentDigest(TARGET_CHAIN_ID, ADDRESSES.hook, intent);

      let signature: Hex;
      let mock = true;
      if (live && walletClient && address) {
        signature = await signIntent(
          walletClient as WalletClient,
          { address } as Account,
          TARGET_CHAIN_ID,
          ADDRESSES.hook,
          intent,
        );
        mock = false;
      } else {
        signature = mockSignature(digest);
      }

      const signed: SignedIntent = {
        id: digest,
        intent,
        signature,
        digest,
        signer: lp,
        chainId: TARGET_CHAIN_ID,
        createdAt: Date.now(),
        mock,
      };
      store.addIntent(signed);
      setResult(signed);
      // advance nonce for the next one
      setNonce(String(nowSec()));
    } catch (err) {
      setError(err instanceof Error ? err.message : String(err));
    } finally {
      setBusy(false);
    }
  }

  return (
    <Card
      title="Create Intent"
      subtitle="Sign an off-chain EIP-712 intent. A permissionless matching engine pairs it into a basket."
    >
      {!live && (
        <Notice kind="mock">
          No wallet connected — intents are signed with a <b>synthetic mock signature</b> against LP{" "}
          <span className="mono">{short(MOCK_LP)}</span>. Connect a wallet to produce real EIP-712
          signatures.
        </Notice>
      )}

      <form onSubmit={onSubmit}>
        <Field label="Pool" hint="bytes32 PoolId">
          <select value={pool} onChange={(e) => setPool(e.target.value as Hex)}>
            {DEMO_POOLS.map((p) => (
              <option key={p.id} value={p.id}>
                {p.label} — {short(p.id, 8, 6)}
              </option>
            ))}
          </select>
        </Field>

        <div className="form-row">
          <Field label="Max Drift" hint="bps (e.g. 250 = 2.5%)">
            <input
              inputMode="numeric"
              value={maxDriftBps}
              onChange={(e) => setMaxDriftBps(e.target.value)}
              placeholder="250"
            />
          </Field>
          <Field label="Min Duration" hint="seconds">
            <input
              inputMode="numeric"
              value={minDuration}
              onChange={(e) => setMinDuration(e.target.value)}
              placeholder="3600"
            />
          </Field>
        </div>

        <div className="form-row">
          <Field label="Max Size" hint="tokens (scaled to 1e18)">
            <input
              inputMode="decimal"
              value={maxSize}
              onChange={(e) => setMaxSize(e.target.value)}
              placeholder="100"
            />
          </Field>
          <Field label="Rep Floor" hint="uint16 min reputation">
            <input
              inputMode="numeric"
              value={repFloor}
              onChange={(e) => setRepFloor(e.target.value)}
              placeholder="0"
            />
          </Field>
        </div>

        <div className="form-row">
          <Field label="Nonce" hint="uint256, must be unused">
            <input value={nonce} onChange={(e) => setNonce(e.target.value)} />
          </Field>
          <Field label="Deadline" hint="unix seconds">
            <input value={deadline} onChange={(e) => setDeadline(e.target.value)} />
          </Field>
        </div>

        <button className="btn primary full" type="submit" disabled={busy}>
          {busy ? "Signing…" : live ? "Sign Intent (EIP-712)" : "Sign Intent (mock)"}
        </button>
      </form>

      {error && (
        <Notice kind="err">
          <span>⚠ {error}</span>
        </Notice>
      )}

      {result && (
        <>
          <hr className="divider" />
          <Notice kind="ok">Intent signed and added to the mempool.</Notice>
          <div className="kv" style={{ marginBottom: 12 }}>
            <dt>Digest</dt>
            <dd className="mono-out">{short(result.digest, 12, 10)}</dd>
            <dt>Signer</dt>
            <dd>{short(result.signer)}</dd>
            <dt>Signature</dt>
            <dd className="mono-out">{short(result.signature, 12, 10)}</dd>
          </div>
          <details>
            <summary className="muted" style={{ cursor: "pointer", marginBottom: 8 }}>
              Show full payload
            </summary>
            <pre className="code">{safeStringify({ ...result })}</pre>
          </details>
        </>
      )}
    </Card>
  );
}
