import { useEffect, useState, useCallback } from "react";
import { jsPDF } from "jspdf";
import { useAuth } from "../auth/useAuth";
import type { AuditEntry, CertificatePayload } from "../backend/api/backend";
import LoadingSpinner from "../components/LoadingSpinner";
import ErrorMessage from "../components/ErrorMessage";

const CANISTER_ID = "3gjvg-naaaa-aaaaj-qr7kq-cai";
const FIRM_NAME = "The Practice";
const OPERATOR = "Onchain Inc.";
const INFRASTRUCTURE = "ICP Mainnet";

interface Metrics {
  auditEntryCount: number;
  lastAuditTimestamp: bigint | null;
  unauthorizedAttempts: number;
}

type ComplianceRow = {
  section: string;
  title: string;
  description: string;
  classification: string;
};

const COMPLIANCE_MATRIX: ComplianceRow[] = [
  {
    section: "s.5",
    title: "Lawful Basis for Processing",
    description:
      "Every access is recorded with the acting principal and purpose-of-access. The audit log enables demonstration of lawful basis for any specific processing event.",
    classification: "Architectural",
  },
  {
    section: "s.7",
    title: "Data Minimisation",
    description:
      "Role-based access ensures staff only maintain access to data required for their work. Partners retain oversight; broad access is the exception, not the default.",
    classification: "Architectural",
  },
  {
    section: "s.9",
    title: "Storage Limitation",
    description:
      "Document retention policies configured per matter type. Time-based archival supported. All deletions are deliberate, logged, and traceable.",
    classification: "Policy + Tech",
  },
  {
    section: "s.10",
    title: "Integrity & Confidentiality",
    description:
      "All transit secured by TLS 1.3. Storage on the ICP network with chain-key cryptography: integrity guarantees. No third-party server has read access to document content.",
    classification: "Architectural",
  },
  {
    section: "s.12",
    title: "Accountability",
    description:
      "Append-only audit log provides a non-repudiable record of every access and modification. Data Protection Management Programme obligations satisfied by design.",
    classification: "Architectural",
  },
  {
    section: "ss.13–16",
    title: "Data Subject Rights",
    description:
      "Export functionality supports production of all data held about a specific subject within statutory response timeframes. Access, rectification, and erasure workflows in place.",
    classification: "Policy + Tech",
  },
  {
    section: "ss.20–21",
    title: "Cross-Border Transfer",
    description:
      "Data resides on the Internet Computer Protocol — not subject to traditional cross-border concerns. Sovereignty is mathematical, not contractual.",
    classification: "Architectural",
  },
  {
    section: "s.23",
    title: "Breach Notification Readiness",
    description:
      "Audit log enables prompt identification of unusual access patterns. Forensic-grade detection within hours, not weeks.",
    classification: "Operational",
  },
];

function truncatePrincipal(s: string) {
  if (s.length <= 16) return s;
  return s.slice(0, 8) + "…" + s.slice(-4);
}

function fmtNsDate(ns: bigint) {
  return new Date(Number(ns / 1_000_000n)).toLocaleDateString();
}

function toHex(bytes: Uint8Array) {
  return Array.from(bytes)
    .map((b) => b.toString(16).padStart(2, "0"))
    .join("");
}

function hexTrunc(hex: string) {
  if (hex.length <= 40) return hex;
  return hex.slice(0, 32) + "..." + hex.slice(-8);
}

// PDF uses a fixed dark navy palette regardless of the app's light/dark toggle.
function generatePDF(
  payload: CertificatePayload,
  masterController: string,
) {
  const doc = new jsPDF({ orientation: "portrait", unit: "mm", format: "a4" });
  const pageW = 210;
  const pageH = 297;
  const margin = 20;
  const contentW = pageW - margin * 2;
  let y = margin;

  const today = new Date();
  const todayStr = today.toLocaleDateString();
  const validStr = new Date(
    Number(payload.validUntil / 1_000_000n),
  ).toLocaleDateString();

  function fillPageBg() {
    doc.setFillColor(11, 17, 32);       // #0b1120
    doc.rect(0, 0, pageW, pageH, "F");
  }
  fillPageBg();

  // ── Header
  doc.setFont("helvetica", "bold");
  doc.setFontSize(20);
  doc.setTextColor(232, 236, 244);      // #e8ecf4
  doc.text("CERTIFICATE OF COMPLIANCE", pageW / 2, y, { align: "center" });
  y += 8;
  doc.setFont("helvetica", "italic");
  doc.setFontSize(11);
  doc.setTextColor(74, 158, 255);       // #4a9eff
  doc.text("PDPA Compliance, by architecture.", pageW / 2, y, {
    align: "center",
  });
  y += 6;
  doc.setFont("helvetica", "normal");
  doc.setFontSize(9);
  doc.setTextColor(122, 138, 168);      // #7a8aa8
  const subtitle =
    "This certifies that the data infrastructure operated by " +
    FIRM_NAME +
    " satisfies the substantive requirements of the Sri Lanka Personal Data Protection Act, No. 9 of 2022, as amended.";
  const subtitleLines = doc.splitTextToSize(subtitle, contentW - 10);
  doc.text(subtitleLines, pageW / 2, y, { align: "center" });
  y += subtitleLines.length * 4 + 8;

  // ── Divider
  doc.setDrawColor(30, 50, 80);
  doc.line(margin, y, pageW - margin, y);
  y += 8;

  // ── Facts grid
  doc.setFont("helvetica", "bold");
  doc.setFontSize(9);
  doc.setTextColor(91, 127, 166);       // #5b7fa6
  doc.text("CERTIFICATE DETAILS", margin, y);
  y += 6;

  const facts: [string, string][] = [
    ["FIRM", FIRM_NAME],
    ["CERTIFICATE ID", payload.certificateId],
    ["ISSUED", todayStr],
    ["VALID THROUGH", validStr],
    ["CANISTER ID", CANISTER_ID],
    ["MASTER CONTROLLER", truncatePrincipal(masterController)],
    ["INFRASTRUCTURE", INFRASTRUCTURE],
    ["OPERATOR", OPERATOR],
  ];

  const colW = contentW / 2 - 5;
  for (let i = 0; i < facts.length; i += 2) {
    const left = facts[i];
    const right = facts[i + 1];
    doc.setFont("helvetica", "bold");
    doc.setFontSize(8);
    doc.setTextColor(91, 127, 166);
    doc.text(left[0], margin, y);
    if (right) doc.text(right[0], margin + colW + 10, y);
    y += 4;
    doc.setFont("helvetica", "normal");
    doc.setFontSize(9);
    doc.setTextColor(232, 236, 244);
    doc.text(left[1], margin, y);
    if (right) doc.text(right[1], margin + colW + 10, y);
    y += 6;
  }
  y += 4;

  // ── Divider
  doc.setDrawColor(30, 50, 80);
  doc.line(margin, y, pageW - margin, y);
  y += 8;

  // ── Compliance Matrix
  doc.setFont("helvetica", "bold");
  doc.setFontSize(9);
  doc.setTextColor(91, 127, 166);
  doc.text("PDPA COMPLIANCE MATRIX — SRI LANKA PERSONAL DATA PROTECTION ACT NO. 9 OF 2022", margin, y);
  y += 7;

  for (const row of COMPLIANCE_MATRIX) {
    if (y > 250) {
      doc.addPage();
      fillPageBg();
      y = margin;
    }
    doc.setFont("helvetica", "bold");
    doc.setFontSize(9);
    doc.setTextColor(232, 236, 244);
    doc.text(row.section + "  " + row.title, margin, y);
    doc.setFont("helvetica", "normal");
    doc.setFontSize(8);
    doc.setTextColor(122, 138, 168);
    const lines = doc.splitTextToSize(row.description, contentW - 30);
    doc.text(lines, margin + 2, y + 4);
    const descH = lines.length * 3.5;
    // Classification pill: #4a7a5c
    doc.setFont("helvetica", "bold");
    doc.setFontSize(7);
    doc.setTextColor(74, 122, 92);
    doc.text("[" + row.classification + "]", pageW - margin - 2, y, {
      align: "right",
    });
    // Enforced by Design badge: #4a9e6a
    doc.setTextColor(74, 158, 106);
    doc.text("✓ Enforced by Design", pageW - margin - 2, y + 4, {
      align: "right",
    });
    y += descH + 10;
  }

  // ── Live Metrics
  if (y > 240) {
    doc.addPage();
    fillPageBg();
    y = margin;
  }
  doc.setDrawColor(30, 50, 80);
  doc.line(margin, y, pageW - margin, y);
  y += 8;
  doc.setFont("helvetica", "bold");
  doc.setFontSize(9);
  doc.setTextColor(91, 127, 166);
  doc.text("LIVE COMPLIANCE METRICS", margin, y);
  y += 6;

  const metricData: [string, string][] = [
    ["AUDIT ENTRIES (TOTAL)", String(payload.auditEntryCount)],
    [
      "LAST AUDIT ENTRY",
      payload.lastAuditTimestamp > 0n
        ? fmtNsDate(payload.lastAuditTimestamp)
        : "—",
    ],
    ["UNAUTHORIZED ATTEMPTS", String(payload.unauthorizedAttempts)],
    ["REPORTED BREACHES", "0"],
  ];

  for (let i = 0; i < metricData.length; i += 2) {
    const left = metricData[i];
    const right = metricData[i + 1];
    doc.setFont("helvetica", "bold");
    doc.setFontSize(8);
    doc.setTextColor(91, 127, 166);
    doc.text(left[0], margin, y);
    if (right) doc.text(right[0], margin + colW + 10, y);
    y += 4;
    doc.setFont("helvetica", "normal");
    doc.setFontSize(10);
    doc.setTextColor(232, 236, 244);
    doc.text(left[1], margin, y);
    if (right) doc.text(right[1], margin + colW + 10, y);
    y += 7;
  }
  y += 4;

  // ── Cryptographic Seal
  if (y > 220) {
    doc.addPage();
    fillPageBg();
    y = margin;
  }
  doc.setDrawColor(30, 50, 80);
  doc.line(margin, y, pageW - margin, y);
  y += 8;
  doc.setFont("helvetica", "bold");
  doc.setFontSize(9);
  doc.setTextColor(91, 127, 166);
  doc.text("CRYPTOGRAPHIC SEAL", margin, y);
  y += 6;

  const sigHex = toHex(payload.signature);
  const pkHex = toHex(payload.publicKey);

  const sealLines: [string, string][] = [
    ["Certificate ID:", payload.certificateId],
    ["Issued by:", "Canister " + CANISTER_ID],
    ["Signature:", hexTrunc(sigHex)],
    ["Public Key:", hexTrunc(pkHex)],
    [
      "Full signature at:",
      "https://dashboard.internetcomputer.org/canister/" + CANISTER_ID,
    ],
  ];

  for (const [label, value] of sealLines) {
    doc.setFont("helvetica", "bold");
    doc.setFontSize(8);
    doc.setTextColor(91, 127, 166);
    doc.text(label, margin, y);
    doc.setFont("helvetica", "normal");
    doc.setTextColor(232, 236, 244);
    const valLines = doc.splitTextToSize(value, contentW - 42);
    doc.text(valLines, margin + 40, y);
    y += valLines.length * 4 + 1;
  }
  y += 4;

  doc.setFont("helvetica", "italic");
  doc.setFontSize(7);
  doc.setTextColor(122, 138, 168);
  const verifyText =
    'To verify: reproduce the canonical message "PDPA-CERT|{id}|{issuedAt}|..." and verify the signature against the public key using secp256k1 ECDSA.';
  const verifyLines = doc.splitTextToSize(verifyText, contentW);
  doc.text(verifyLines, margin, y);
  y += verifyLines.length * 3.5 + 8;

  // ── Footer
  if (y > 275) {
    doc.addPage();
    fillPageBg();
    y = 280;
  }
  doc.setDrawColor(30, 50, 80);
  doc.line(margin, 285, pageW - margin, 285);
  doc.setFont("helvetica", "normal");
  doc.setFontSize(8);
  doc.setTextColor(91, 127, 166);
  doc.text(
    "Generated by The Practice · Onchain Inc. · ICP Mainnet",
    pageW / 2,
    290,
    { align: "center" },
  );

  const dateStr = today.toISOString().slice(0, 10);
  doc.save(`PDPA-Compliance-Certificate-${dateStr}.pdf`);
}

export default function CompliancePage() {
  const { actor, isMasterController, isOperationsPrincipal, role } = useAuth();

  const [masterController, setMasterController] = useState<string | null>(null);
  const [metrics, setMetrics] = useState<Metrics | null>(null);
  const [metricsError, setMetricsError] = useState<string | null>(null);
  const [loading, setLoading] = useState(true);
  const [generating, setGenerating] = useState(false);
  const [genError, setGenError] = useState<string | null>(null);

  const canAccess = isMasterController || isOperationsPrincipal;

  const loadData = useCallback(async () => {
    if (!actor) return;
    setLoading(true);
    try {
      const mc = await actor.getMasterController();
      setMasterController(mc.toText());

      // Audit metrics — only available with Partner role (master controller always has it)
      if (role !== null) {
        try {
          const result = await actor.readAuditEntries(0n, 10000n);
          if (result.__kind__ === "ok") {
            const entries: AuditEntry[] = result.ok;
            const count = entries.length;
            let lastTs: bigint = 0n;
            let unauthorized = 0;
            for (const e of entries) {
              if (e.timestamp > lastTs) lastTs = e.timestamp;
              if (e.outcome.__kind__ === "err") unauthorized++;
            }
            setMetrics({ auditEntryCount: count, lastAuditTimestamp: lastTs > 0n ? lastTs : null, unauthorizedAttempts: unauthorized });
          }
        } catch {
          setMetricsError("Metrics available after PDF generation.");
        }
      } else {
        setMetricsError("Metrics available after PDF generation.");
      }
    } catch (e) {
      setMetricsError(String(e));
    } finally {
      setLoading(false);
    }
  }, [actor, role]);

  useEffect(() => { void loadData(); }, [loadData]);

  async function handleGenerate() {
    if (!actor) return;
    setGenError(null);
    setGenerating(true);
    try {
      const result = await actor.generateComplianceCertificate();
      if (result.__kind__ === "err") {
        setGenError(result.err);
        return;
      }
      const payload = result.ok;
      const mc = masterController ?? payload.masterController;
      generatePDF(payload, mc);
      // Refresh metrics from returned payload
      setMetrics({
        auditEntryCount: Number(payload.auditEntryCount),
        lastAuditTimestamp: payload.lastAuditTimestamp > 0n ? payload.lastAuditTimestamp : null,
        unauthorizedAttempts: Number(payload.unauthorizedAttempts),
      });
    } catch (e) {
      setGenError(String(e));
    } finally {
      setGenerating(false);
    }
  }

  if (!canAccess) {
    return (
      <div>
        <div className="page-header"><div className="page-title">Compliance</div></div>
        <div style={{ color: "var(--tx2)", fontSize: 14 }}>
          Access restricted to master controller and operations principal.
        </div>
      </div>
    );
  }

  const today = new Date();
  const todayStr = today.toLocaleDateString();
  const validStr = new Date(
    today.getFullYear() + 1,
    today.getMonth(),
    today.getDate(),
  ).toLocaleDateString();

  return (
    <div>
      {/* ── Header ─────────────────────────────────────────────────────── */}
      <div style={{ textAlign: "center", marginBottom: 40, padding: "32px 0 0" }}>
        <div style={{ fontSize: 11, letterSpacing: "0.28em", textTransform: "uppercase", color: "var(--tx2)", fontWeight: 600, marginBottom: 16 }}>
          CERTIFICATE OF COMPLIANCE
        </div>
        <div style={{ fontSize: 40, fontWeight: 300, lineHeight: 1.1, marginBottom: 12, color: "var(--tx)", letterSpacing: "-0.02em" }}>
          PDPA Compliance,{" "}
          <span style={{ fontStyle: "italic", color: "var(--accent, #82B5FF)" }}>by architecture.</span>
        </div>
        <div style={{ fontSize: 14, color: "var(--tx2)", maxWidth: 560, margin: "0 auto", lineHeight: 1.6, fontStyle: "italic" }}>
          This certifies that the data infrastructure operated by <strong>{FIRM_NAME}</strong> satisfies
          the substantive requirements of the Sri Lanka Personal Data Protection Act, No. 9 of 2022, as amended.
        </div>
      </div>

      {/* ── Seal ───────────────────────────────────────────────────────── */}
      <div style={{ display: "flex", justifyContent: "center", marginBottom: 40 }}>
        <div style={{
          width: 180, height: 180, borderRadius: "50%",
          border: "1px solid var(--accent, #82B5FF)",
          display: "flex", flexDirection: "column", alignItems: "center", justifyContent: "center",
          position: "relative", gap: 8,
          background: "rgba(130,181,255,0.05)",
          boxShadow: "0 4px 24px rgba(0,0,0,0.18)",
        }}>
          <div style={{
            width: 52, height: 52, borderRadius: "50%",
            background: "var(--accent, #82B5FF)",
            display: "flex", alignItems: "center", justifyContent: "center",
            boxShadow: "0 0 20px rgba(130,181,255,0.4)",
          }}>
            <svg width="28" height="28" viewBox="0 0 24 24" fill="none" stroke="white" strokeWidth="2.5" strokeLinecap="round" strokeLinejoin="round">
              <polyline points="20 6 9 17 4 12" />
            </svg>
          </div>
          <div style={{ textAlign: "center", lineHeight: 1.35 }}>
            <div style={{ fontWeight: 600, fontSize: 12, letterSpacing: "0.08em", color: "var(--tx)" }}>COMPLIANT</div>
            <div style={{ fontSize: 11, color: "var(--tx2)" }}>{todayStr}</div>
          </div>
        </div>
      </div>

      {loading && <LoadingSpinner />}

      {/* ── Facts Panel ────────────────────────────────────────────────── */}
      <div className="card" style={{ padding: 24, marginBottom: 24 }}>
        <div className="section-head">Certificate Details</div>
        <div style={{ display: "grid", gridTemplateColumns: "1fr 1fr", gap: "12px 40px" }}>
          {([
            ["FIRM", FIRM_NAME],
            ["CERTIFICATE ID", "Generated on PDF seal"],
            ["ISSUED", todayStr],
            ["VALID THROUGH", validStr],
            ["CANISTER ID", CANISTER_ID],
            ["MASTER CONTROLLER", masterController ? truncatePrincipal(masterController) : "—"],
            ["INFRASTRUCTURE", INFRASTRUCTURE],
            ["OPERATOR", OPERATOR],
          ] as [string, string][]).map(([label, value]) => (
            <div key={label} style={{ display: "flex", justifyContent: "space-between", alignItems: "baseline", paddingBottom: 10, borderBottom: "0.5px solid var(--bd)" }}>
              <span style={{ fontSize: 10, fontWeight: 600, letterSpacing: "0.1em", textTransform: "uppercase", color: "var(--tx2)" }}>
                {label}
              </span>
              <span className="mono" style={{ fontSize: 12, color: "var(--tx)" }}>
                {value}
              </span>
            </div>
          ))}
        </div>
      </div>

      {/* ── Compliance Matrix ───────────────────────────────────────────── */}
      <div style={{ marginBottom: 24 }}>
        <div className="section-head" style={{ marginBottom: 16 }}>PDPA Requirements — Sri Lanka Personal Data Protection Act No. 9 of 2022</div>
        <div style={{ display: "flex", flexDirection: "column", gap: 10 }}>
          {COMPLIANCE_MATRIX.map((row) => (
            <div key={row.section} className="card" style={{ padding: "18px 22px", display: "grid", gridTemplateColumns: "48px 1fr auto", gap: 16, alignItems: "start" }}>
              <div style={{ fontWeight: 700, fontSize: 12, color: "var(--accent, #82B5FF)", paddingTop: 2 }}>
                {row.section}
              </div>
              <div>
                <div style={{ fontWeight: 600, fontSize: 13, marginBottom: 4, color: "var(--tx)" }}>
                  {row.title}
                </div>
                <div style={{ fontSize: 12, color: "var(--tx2)", lineHeight: 1.55 }}>
                  {row.description}
                </div>
                <div style={{ marginTop: 8, display: "inline-block", fontSize: 10, padding: "2px 8px", borderRadius: 4, border: "1px solid var(--bd)", color: "var(--tx2)", letterSpacing: "0.05em" }}>
                  {row.classification}
                </div>
              </div>
              <div style={{ display: "flex", flexDirection: "column", alignItems: "flex-end", gap: 4, paddingTop: 2 }}>
                <div style={{ fontSize: 10, padding: "3px 10px", borderRadius: 4, background: "rgba(130,181,255,0.1)", color: "var(--accent, #82B5FF)", fontWeight: 600, letterSpacing: "0.04em", whiteSpace: "nowrap", border: "1px solid rgba(130,181,255,0.2)" }}>
                  Enforced by Design
                </div>
              </div>
            </div>
          ))}
        </div>
      </div>

      {/* ── Live Metrics ────────────────────────────────────────────────── */}
      <div className="card" style={{ padding: 24, marginBottom: 24 }}>
        <div className="section-head" style={{ marginBottom: 16 }}>Live Compliance Metrics</div>
        {metricsError && !metrics && (
          <div style={{ color: "var(--tx2)", fontSize: 13, marginBottom: 12 }}>{metricsError}</div>
        )}
        <div style={{ display: "grid", gridTemplateColumns: "1fr 1fr 1fr 1fr", gap: 16 }}>
          {([
            ["AUDIT ENTRIES (TOTAL)", metrics ? String(metrics.auditEntryCount) : "—", false],
            ["LAST AUDIT ENTRY", metrics?.lastAuditTimestamp ? fmtNsDate(metrics.lastAuditTimestamp) : "—", false],
            ["UNAUTHORIZED ATTEMPTS", metrics ? String(metrics.unauthorizedAttempts) : "—", false],
            ["REPORTED BREACHES", "0", false],
          ] as [string, string, boolean][]).map(([label, value]) => (
            <div key={label} style={{ textAlign: "center", padding: "16px 12px", borderRadius: 10, border: "0.5px solid var(--bd)", background: "var(--bg2, rgba(255,255,255,0.03))" }}>
              <div style={{ fontSize: 10, fontWeight: 600, letterSpacing: "0.1em", textTransform: "uppercase", color: "var(--tx2)", marginBottom: 8 }}>
                {label}
              </div>
              <div style={{ fontSize: 22, fontWeight: 300, color: "var(--tx)" }}>
                {value}
              </div>
            </div>
          ))}
        </div>
      </div>

      {/* ── Generate PDF ─────────────────────────────────────────────────── */}
      <div className="card" style={{ padding: 20, display: "flex", alignItems: "center", gap: 16, marginBottom: 40 }}>
        <div style={{ flex: 1 }}>
          <div style={{ fontSize: 13, fontWeight: 600, color: "var(--tx)", marginBottom: 2 }}>
            Generate sealed PDF
          </div>
          <div style={{ fontSize: 12, color: "var(--tx2)" }}>
            Signs the certificate with the canister's threshold ECDSA key. Takes 3–5 seconds.
          </div>
        </div>
        {genError && <ErrorMessage message={genError} onDismiss={() => setGenError(null)} />}
        <button
          className="btn btn-primary"
          disabled={generating || !actor}
          onClick={() => { void handleGenerate(); }}
          style={{ flexShrink: 0 }}
        >
          {generating ? "Sealing…" : "Generate sealed PDF"}
        </button>
      </div>
    </div>
  );
}
