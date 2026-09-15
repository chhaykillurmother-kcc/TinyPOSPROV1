import { useEffect, useState } from "react";
import Modal from "./Modal";
import { useLanguage } from "../context/LanguageContext";

export default function AccountingMappingModal({ mapping, accounts, busy, onClose, onSave }) {
  const { t } = useLanguage();
  const [accountId, setAccountId] = useState("");
  useEffect(() => { setAccountId(mapping?.account_id || ""); }, [mapping]);
  return <Modal title={t("Update accounting mapping")} onClose={onClose} className="accounting-mapping-modal">
    <form className="form-stack" onSubmit={(event) => { event.preventDefault(); onSave({ mapping_key: mapping.mapping_key, account_id: accountId }); }}>
      <div className="mapping-key-card"><strong>{t(mapping?.mapping_key?.replaceAll("_", " "))}</strong><small>{t(mapping?.description || "Operational posting mapping")}</small></div>
      <label><span>{t("Post to account")}</span><select value={accountId} onChange={(e) => setAccountId(e.target.value)} required><option value="">{t("Select account")}</option>{accounts.filter((a) => a.is_active).map((a) => <option key={a.id} value={a.id}>{a.code} — {t(a.name)}</option>)}</select></label>
      <div className="modal-actions"><button type="button" className="secondary-button" onClick={onClose}>{t("Cancel")}</button><button type="submit" className="primary-button" disabled={busy}>{busy ? t("Saving...") : t("Save mapping")}</button></div>
    </form>
  </Modal>;
}

