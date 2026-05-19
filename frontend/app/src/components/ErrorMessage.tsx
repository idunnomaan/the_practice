interface Props {
  message: string;
  onDismiss?: () => void;
}

export default function ErrorMessage({ message, onDismiss }: Props) {
  return (
    <div style={{ background: "#fff0f0", border: "1px solid #f00", padding: "0.75rem 1rem", marginBottom: "1rem", borderRadius: 4 }}>
      <span style={{ color: "#c00" }}>{message}</span>
      {onDismiss && (
        <button onClick={onDismiss} style={{ marginLeft: "1rem", background: "none", border: "none", cursor: "pointer", color: "#888" }}>
          ✕
        </button>
      )}
    </div>
  );
}
