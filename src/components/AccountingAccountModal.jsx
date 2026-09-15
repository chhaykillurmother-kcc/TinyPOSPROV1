import { useEffect, useState } from "react";
import Modal from "./Modal";
import { useLanguage } from "../context/LanguageContext";

const EMPTY = { code: "", name: "", account_type: "asset", normal_balance: "debit", is_active: true, description: "" };

export default function AccountingAccountModal({ account, busy, onClose, onSave }) {
  const { t } = useLanguage();
  const [values, setValues] = useState(EMPTY);
  useEffect(() => { setValues(account ? { ...EMPTY, ...account } : EMPTY); }, [account]);
  function set(key, value) { setValues((current) => ({ ...current, [key]: value })); }
  function submit(event) { event.preventDefault(); onSave(values); }
  return <Modal title={account ? t("Edit account") : t("New account")} onClose={onClose} className="accounting-account-modal">
    <form className="form-stack" onSubmit={submit}>
      <div className="form-grid two-columns two">
        <label><span>{t("Account code")}</span><input value={values.code} onChange={(e) => set("code", e.target.value)} required disabled={Boolean(account?.is_system)} placeholder="6100" /></label>
        <label><span>{t("Account name")}</span><input value={values.name} onChange={(e) => set("name", e.target.value)} required placeholder={t("Professional Services")} /></label>
        <label><span>{t("Account type")}</span><select value={values.account_type} onChange={(e) => set("account_type", e.target.value)}><option value="asset">{t("Asset")}</option><option value="liability">{t("Liability")}</option><option value="equity">{t("Equity")}</option><option value="income">{t("Income")}</option><option value="expense">{t("Expense")}</option></select></label>
        <label><span>{t("Normal balance")}</span><select value={values.normal_balance} onChange={(e) => set("normal_balance", e.target.value)}><option value="debit">{t("Debit")}</option><option value="credit">{t("Credit")}</option></select></label>
      </div>
      <label><span>{t("Description")}</span><textarea value={values.description || ""} onChange={(e) => set("description", e.target.value)} rows="3" /></label>
      <label className="form-check"><input className="form-check-input" type="checkbox" checked={Boolean(values.is_active)} onChange={(e) => set("is_active", e.target.checked)} /><span className="form-check-label">{t("Active account")}</span></label>
      <div className="modal-actions"><button type="button" className="secondary-button" onClick={onClose}>{t("Cancel")}</button><button type="submit" className="primary-button" disabled={busy}>{busy ? t("Saving...") : t("Save account")}</button></div>
    </form>
  </Modal>;
}

