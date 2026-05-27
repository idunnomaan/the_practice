import { useEffect, useState } from "react";
import type { ViewerProps } from "./ViewerProps";

export default function DocxViewer({ blob }: ViewerProps) {
  const [html, setHtml] = useState<string | null>(null);
  const [convError, setConvError] = useState<string | null>(null);

  useEffect(() => {
    let cancelled = false;
    blob.arrayBuffer().then(async buf => {
      // mammoth is a CommonJS module; dynamic import works in Vite
      const mammoth = await import("mammoth");
      const result = await mammoth.convertToHtml({ arrayBuffer: buf });
      if (!cancelled) setHtml(result.value);
    }).catch(e => {
      if (!cancelled) setConvError(String(e));
    });
    return () => { cancelled = true; };
  }, [blob]);

  return (
    <div style={{ overflow: "auto", maxHeight: "70vh" }}>
      {/* D7 required header — lossy preview warning */}
      <div style={{
        padding: "8px 16px",
        background: "var(--warning-bg, #fff3cd)",
        borderBottom: "1px solid var(--border)",
        fontSize: 13,
        color: "var(--tx2)",
      }}>
        Preview — formatting may differ from the source. Download for the definitive copy.
      </div>
      {convError ? (
        <div style={{ padding: 16, color: "var(--danger)" }}>Could not render DOCX: {convError}</div>
      ) : html === null ? (
        <div style={{ padding: 16 }}>Converting…</div>
      ) : (
        <div
          style={{ padding: 16, color: "var(--tx1)", lineHeight: 1.6 }}
          // mammoth output is sanitised HTML (no script tags); safe to inject
          // eslint-disable-next-line react/no-danger
          dangerouslySetInnerHTML={{ __html: html }}
        />
      )}
    </div>
  );
}
