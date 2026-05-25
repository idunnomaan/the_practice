import { useState } from "react";

interface Props {
  principal: string;
  label?: string;
}

export default function PrincipalDisplay({ principal, label }: Props) {
  const [copied, setCopied] = useState(false);

  async function copy() {
    await navigator.clipboard.writeText(principal);
    setCopied(true);
    setTimeout(() => setCopied(false), 1500);
  }

  return (
    <div style={{ display: "flex", alignItems: "center", gap: 8, flexWrap: "wrap" }}>
      {label && <span style={{ color: "var(--tx2)", fontSize: 13 }}>{label}:</span>}
      <code style={{ fontSize: 12, wordBreak: "break-all", color: "var(--tx)" }}>{principal}</code>
      <button
        className="btn btn-neutral btn-sm"
        onClick={() => { void copy(); }}
        style={{ flexShrink: 0 }}
      >
        {copied ? <><i className="ti ti-check" /> Copied</> : <><i className="ti ti-copy" /> Copy</>}
      </button>
    </div>
  );
}
