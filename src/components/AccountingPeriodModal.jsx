import { useState } from "react";
import Modal from "./Modal";
import { useLanguage } from "../context/LanguageContext";

export default function AccountingPeriodModal({ branches, busy, onClose, onSave }) {
  const { t, language } = useLanguage();
  const now = new Date();
  const [values, setValues] = useState({ branch_id: "", year: now.getFullYear(), month: now.getMonth() + 1, status: "closed", notes: "" });
  function set(key, value) { setValues((current) => ({ ...current, [key]: value })); }
  return <Modal title={t("Accounting period")} onClose={onClose} className="accounting-period-modal">
    <form className="form-stack" onSubmit={(event) => { event.preventDefault(); onSave(values); }}>
      <label><span>{t("Scope")}</span><select value={values.branch_id} onChange={(e) => set("branch_id", e.target.value)}><option value="">{t("All branches")}</option>{branches.map((b) => <option key={b.id} value={b.id}>{b.name}</option>)}</select></label>
      <div className="form-grid two-columns two"><label><span>{t("Year")}</span><input type="number" min="2000" max="2200" value={values.year} onChange={(e) => set("year", e.target.value)} /></label><label><span>{t("Month")}</span><select value={values.month} onChange={(e) => set("month", e.target.value)}>{Array.from({ length: 12 }, (_, i) => <option key={i + 1} value={i + 1}>{new Intl.DateTimeFormat(language === "km" ? "km-KH" : "en-US", { month: "long" }).format(new Date(2026, i, 1))}</option>)}</select></label></div>
      <label><span>{t("Status")}</span><select value={values.status} onChange={(e) => set("status", e.target.value)}><option value="closed">{t("Close period")}</option><option value="open">{t("Reopen period")}</option></select></label>
      <label><span>{t("Notes")}</span><textarea rows="3" value={values.notes} onChange={(e) => set("notes", e.target.value)} placeholder={t("Optional closing note")} /></label>
      <div className="notice warning">{t("Closing a period blocks new, edited or voided manual accounting journals for that period. It does not stop normal POS sales or purchases.")}</div>
      <div className="modal-actions"><button type="button" className="secondary-button" onClick={onClose}>{t("Cancel")}</button><button type="submit" className="primary-button" disabled={busy}>{busy ? t("Saving...") : t("Save period")}</button></div>
    </form>
  </Modal>;
}

