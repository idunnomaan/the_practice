interface Props {
  message: string;
  onConfirm: () => void;
  onCancel: () => void;
}

export default function ConfirmDialog({ message, onConfirm, onCancel }: Props) {
  return (
    <div style={{
      position: "fixed", inset: 0, background: "rgba(0,0,0,0.4)",
      display: "flex", alignItems: "center", justifyContent: "center", zIndex: 100,
    }}>
      <div style={{ background: "#fff", padding: "2rem", borderRadius: 8, maxWidth: 400, width: "90%" }}>
        <p style={{ marginTop: 0 }}>{message}</p>
        <div style={{ display: "flex", gap: "1rem", justifyContent: "flex-end" }}>
          <button onClick={onCancel} style={{ padding: "0.5rem 1rem" }}>Cancel</button>
          <button onClick={onConfirm} style={{ padding: "0.5rem 1rem", background: "#c00", color: "#fff", border: "none", borderRadius: 4, cursor: "pointer" }}>
            Confirm
          </button>
        </div>
      </div>
    </div>
  );
}
