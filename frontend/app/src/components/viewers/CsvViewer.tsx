import { useEffect, useState } from "react";
import type { ViewerProps } from "./ViewerProps";

function parseCsv(raw: string): string[][] {
  return raw
    .split(/\r?\n/)
    .filter(line => line.trim().length > 0)
    .map(line => {
      const cells: string[] = [];
      let current = "";
      let inQuotes = false;
      for (let i = 0; i < line.length; i++) {
        const ch = line[i];
        if (ch === '"') {
          if (inQuotes && line[i + 1] === '"') { current += '"'; i++; }
          else inQuotes = !inQuotes;
        } else if (ch === "," && !inQuotes) {
          cells.push(current); current = "";
        } else {
          current += ch;
        }
      }
      cells.push(current);
      return cells;
    });
}

export default function CsvViewer({ blob }: ViewerProps) {
  const [rows, setRows] = useState<string[][] | null>(null);

  useEffect(() => {
    blob.text().then(text => setRows(parseCsv(text))).catch(() => setRows([]));
  }, [blob]);

  if (rows === null) return <div style={{ padding: 16 }}>Loading…</div>;
  if (rows.length === 0) return <div style={{ padding: 16, color: "var(--tx2)" }}>Empty or unreadable CSV.</div>;

  const headers = rows[0];
  const body = rows.slice(1);

  return (
    <div style={{ overflow: "auto", maxHeight: "70vh", padding: 8 }}>
      <table className="tp-table" style={{ minWidth: "100%" }}>
        <thead>
          <tr>{headers.map((h, i) => <th key={i}>{h}</th>)}</tr>
        </thead>
        <tbody>
          {body.map((row, ri) => (
            <tr key={ri}>{headers.map((_, ci) => <td key={ci}>{row[ci] ?? ""}</td>)}</tr>
          ))}
        </tbody>
      </table>
    </div>
  );
}
