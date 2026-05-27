import { useEffect, useState, useCallback } from "react";
import { useAuth } from "../auth/useAuth";
import { FileAccessKind } from "../backend/api/backend";
import { useFileViewer } from "../state/fileViewerStore";
import { fetchAndAssembleBlob } from "../utils/fetchAndAssembleBlob";
import { chooseViewer } from "../utils/chooseViewer";

const LARGE_VIDEO_BYTES = 500_000_000n;
const LARGE_FILE_BYTES = 200_000_000n;

export default function FileViewerModal() {
  const { actor } = useAuth();
  const { state, closeViewer } = useFileViewer();
  const { open, source } = state;

  const [loading, setLoading] = useState(false);
  const [loadError, setLoadError] = useState<string | null>(null);
  const [assembled, setAssembled] = useState<{ url: string; blob: Blob; filename: string; contentType: string } | null>(null);
  // D6: pre-fetch confirmation for large videos
  const [awaitingVideoConfirm, setAwaitingVideoConfirm] = useState(false);
  const [downloadingFooter, setDownloadingFooter] = useState(false);

  const isLargeVideo = source
    ? source.contentType.toLowerCase().startsWith("video/") && source.sizeBytes > LARGE_VIDEO_BYTES
    : false;

  const isLargeNonVideo = source && !source.contentType.toLowerCase().startsWith("video/")
    ? source.sizeBytes > LARGE_FILE_BYTES
    : false;

  const fetchBlob = useCallback(async () => {
    if (!actor || !source) return;
    setLoading(true);
    setLoadError(null);
    try {
      const result = await fetchAndAssembleBlob({
        prepare: async () => {
          const r = source.kind === "document"
            ? await actor.prepareDocumentDownload(source.versionId, FileAccessKind.View)
            : await actor.prepareLibraryDownload(source.versionId, FileAccessKind.View);
          if (r.__kind__ === "err") throw new Error(r.err);
          return {
            chunkCount: r.ok.chunkCount,
            contentType: r.ok.contentType,
            filename: r.ok.filename,
          };
        },
        getChunk: async (i) => {
          if (source.kind === "document") {
            return actor.getChunk(source.versionId, i);
          } else {
            return actor.getLibraryChunk(source.versionId, i);
          }
        },
      });
      setAssembled(result);
    } catch (e) {
      setLoadError(String(e));
    } finally {
      setLoading(false);
    }
  }, [actor, source]);

  // When modal opens: check for large-video gating, otherwise fetch immediately
  useEffect(() => {
    if (!open || !source) {
      setAssembled(null);
      setLoadError(null);
      setAwaitingVideoConfirm(false);
      return;
    }
    if (isLargeVideo) {
      setAwaitingVideoConfirm(true);
    } else {
      void fetchBlob();
    }
  }, [open, source]); // eslint-disable-line react-hooks/exhaustive-deps

  // Revoke blob URL when modal closes (D7 cleanup: URL.revokeObjectURL)
  useEffect(() => {
    if (!open && assembled) {
      URL.revokeObjectURL(assembled.url);
    }
  }, [open]); // eslint-disable-line react-hooks/exhaustive-deps

  // Footer download — triggers fresh #Download call + browser save
  const handleFooterDownload = useCallback(async () => {
    if (!actor || !source || downloadingFooter) return;
    setDownloadingFooter(true);
    try {
      const result = await fetchAndAssembleBlob({
        prepare: async () => {
          const r = source.kind === "document"
            ? await actor.prepareDocumentDownload(source.versionId, FileAccessKind.Download)
            : await actor.prepareLibraryDownload(source.versionId, FileAccessKind.Download);
          if (r.__kind__ === "err") throw new Error(r.err);
          return {
            chunkCount: r.ok.chunkCount,
            contentType: r.ok.contentType,
            filename: r.ok.filename,
          };
        },
        getChunk: async (i) => {
          if (source.kind === "document") {
            return actor.getChunk(source.versionId, i);
          } else {
            return actor.getLibraryChunk(source.versionId, i);
          }
        },
      });
      const a = document.createElement("a");
      a.href = result.url;
      a.download = result.filename;
      a.click();
      URL.revokeObjectURL(result.url);
    } catch {
      // silent — download failed, user can try again
    } finally {
      setDownloadingFooter(false);
    }
  }, [actor, source, downloadingFooter]);

  const handleClose = useCallback(() => {
    if (assembled) URL.revokeObjectURL(assembled.url);
    setAssembled(null);
    setLoadError(null);
    setLoading(false);
    closeViewer();
  }, [assembled, closeViewer]);

  if (!open || !source) return null;

  const Viewer = assembled ? chooseViewer(assembled.contentType) : null;

  // D6: large-video pre-fetch confirmation dialog
  if (awaitingVideoConfirm) {
    return (
      <div style={overlayStyle}>
        <div style={{ ...panelStyle, maxWidth: 420, textAlign: "center" }}>
          <p style={{ marginBottom: 16 }}>
            This video is over 500 MB. Streaming inside the app may buffer slowly.{" "}
            <strong>For best playback, download the file.</strong>
          </p>
          <div style={{ display: "flex", gap: 8, justifyContent: "center" }}>
            <button
              className="btn btn-primary"
              autoFocus
              onClick={() => { void handleFooterDownload(); setAwaitingVideoConfirm(false); closeViewer(); }}
            >
              Download
            </button>
            <button
              className="btn btn-neutral"
              onClick={() => { setAwaitingVideoConfirm(false); void fetchBlob(); }}
            >
              Play anyway
            </button>
          </div>
        </div>
      </div>
    );
  }

  return (
    <div style={overlayStyle} onClick={e => { if (e.target === e.currentTarget) handleClose(); }}>
      <div style={panelStyle}>
        {/* Header */}
        <div style={{ display: "flex", alignItems: "center", gap: 12, padding: "12px 16px", borderBottom: "1px solid var(--border)" }}>
          <span style={{ flex: 1, fontWeight: 600, fontSize: 14, overflow: "hidden", textOverflow: "ellipsis", whiteSpace: "nowrap" }}>
            {source.filename}
          </span>
          <button className="btn btn-neutral btn-sm" onClick={handleClose} style={{ flexShrink: 0 }}>
            <i className="ti ti-x" />
          </button>
        </div>

        {/* D6: large non-video inline banner while loading */}
        {isLargeNonVideo && loading && (
          <div style={{ padding: "6px 16px", background: "var(--warning-bg, #fff3cd)", fontSize: 12, color: "var(--tx2)", borderBottom: "1px solid var(--border)" }}>
            Large file — preview may take a moment to load.
          </div>
        )}

        {/* Body */}
        <div style={{ flex: 1, overflow: "auto", minHeight: 200 }}>
          {loading && <div style={{ padding: 32, textAlign: "center", color: "var(--tx2)" }}>Loading…</div>}
          {loadError && <div style={{ padding: 16, color: "var(--danger)" }}>Failed to load: {loadError}</div>}
          {Viewer && assembled && (
            <Viewer
              url={assembled.url}
              blob={assembled.blob}
              filename={assembled.filename}
              contentType={assembled.contentType}
              sizeBytes={source.sizeBytes}
              onDownload={() => { void handleFooterDownload(); }}
            />
          )}
        </div>

        {/* Footer */}
        <div style={{ display: "flex", gap: 8, justifyContent: "flex-end", padding: "12px 16px", borderTop: "1px solid var(--border)" }}>
          <button
            className="btn btn-neutral btn-sm"
            onClick={() => { void handleFooterDownload(); }}
            disabled={downloadingFooter}
          >
            {downloadingFooter ? "…" : "Download"}
          </button>
          <button className="btn btn-neutral btn-sm" onClick={handleClose}>Close</button>
        </div>
      </div>
    </div>
  );
}

const overlayStyle: React.CSSProperties = {
  position: "fixed",
  inset: 0,
  background: "rgba(0,0,0,0.55)",
  display: "flex",
  alignItems: "center",
  justifyContent: "center",
  zIndex: 200,
};

const panelStyle: React.CSSProperties = {
  background: "var(--bg1)",
  borderRadius: 8,
  width: "min(90vw, 960px)",
  maxHeight: "90vh",
  display: "flex",
  flexDirection: "column",
  overflow: "hidden",
  boxShadow: "0 8px 32px rgba(0,0,0,0.4)",
};
