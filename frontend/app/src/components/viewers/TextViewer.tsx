import { useEffect, useState } from "react";
import type { ViewerProps } from "./ViewerProps";

export default function TextViewer({ blob }: ViewerProps) {
  const [text, setText] = useState<string | null>(null);

  useEffect(() => {
    blob.text().then(setText).catch(() => setText("(could not decode text)"));
  }, [blob]);

  if (text === null) return <div style={{ padding: 16 }}>Loading…</div>;

  return (
    <pre style={{
      padding: 16,
      margin: 0,
      overflow: "auto",
      maxHeight: "70vh",
      fontFamily: "monospace",
      fontSize: 13,
      whiteSpace: "pre-wrap",
      wordBreak: "break-word",
      color: "var(--tx1)",
      background: "var(--bg2)",
    }}>
      {text}
    </pre>
  );
}
