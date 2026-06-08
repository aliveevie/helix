import type { ReactNode } from "react";

export function Card({
  title,
  subtitle,
  actions,
  children,
}: {
  title?: string;
  subtitle?: ReactNode;
  actions?: ReactNode;
  children: ReactNode;
}) {
  return (
    <section className="card">
      {(title || actions) && (
        <div className="card-head">
          <div>
            {title && <h2>{title}</h2>}
            {subtitle && <div className="sub">{subtitle}</div>}
          </div>
          {actions}
        </div>
      )}
      <div className="card-body">{children}</div>
    </section>
  );
}

export function Field({
  label,
  hint,
  children,
}: {
  label: string;
  hint?: ReactNode;
  children: ReactNode;
}) {
  return (
    <div className="field">
      <label>
        {label} {hint && <span className="hint">· {hint}</span>}
      </label>
      {children}
    </div>
  );
}

export function Empty({ children }: { children: ReactNode }) {
  return <div className="empty">{children}</div>;
}

export function Notice({
  kind = "info",
  children,
}: {
  kind?: "info" | "mock" | "err" | "ok";
  children: ReactNode;
}) {
  const cls = kind === "info" ? "notice" : `notice ${kind}`;
  return <div className={cls}>{children}</div>;
}

export function Tag({
  color,
  children,
}: {
  color?: "green" | "cyan" | "violet" | "amber" | "dim";
  children: ReactNode;
}) {
  return <span className={color ? `tag ${color}` : "tag"}>{children}</span>;
}

export function Pill({
  kind,
  children,
}: {
  kind?: "ok" | "warn" | "bad" | "mock";
  children: ReactNode;
}) {
  return (
    <span className={kind ? `pill ${kind}` : "pill"}>
      <span className="dot" />
      {children}
    </span>
  );
}

export function Spinner() {
  return <span className="spinner" />;
}
