import { useEffect, useState } from "react";
import Modal from "./Modal";
import { useLanguage } from "../context/LanguageContext";
import { monthRange } from "../lib/staffOperations";

export default function CommissionPayoutModal({ staff, branches, defaults = null, busy, onClose, onSave }) {
  const { t } = useLanguage();
  const range = monthRange();
  const [values, setValues] = useState({
    user_id: "",
    branch_id: "",
    currency: "USD",
    period_start: range.start,
    period_end: range.end,
    amount: "",
    payment_method: "cash",
    reference_number: "",
    notes: ""
  });

  useEffect(() => {
    if (!defaults) return;
    setValues((current) => ({ ...current, ...defaults }));
  }, [defaults]);

  function change(event) {
    const { name, value } = event.target;
    setValues((current) => ({ ...current, [name]: value }));
  }

  function handleSubmit(event) {
    event.preventDefault();
    if (busy || !values.user_id || !values.branch_id || Number(values.amount) <= 0) return;
    onSave(values);
  }

  return (
    <Modal
      title={t("Record staff payment")}
      onClose={onClose}
      className="staff-modal"
    >
      <form onSubmit={handleSubmit} className="staff-modal-form">
        <div className="form-grid two-columns">
          <label>
            <span>{t("Staff member")} *</span>
            <select name="user_id" value={values.user_id} onChange={change} required>
              <option value="">{t("Select staff")}</option>
              {staff.map((row) => (
                <option key={row.id} value={row.id}>
                  {row.full_name}
                </option>
              ))}
            </select>
          </label>
          <label>
            <span>{t("Branch")} *</span>
            <select name="branch_id" value={values.branch_id} onChange={change} required>
              <option value="">{t("Select branch")}</option>
              {branches.map((row) => (
                <option key={row.id} value={row.id}>
                  {row.name}
                </option>
              ))}
            </select>
          </label>
          <label>
            <span>{t("Currency")}</span>
            <select name="currency" value={values.currency} onChange={change}>
              <option value="USD">USD</option>
              <option value="KHR">KHR</option>
            </select>
          </label>
          <label>
            <span>{t("Amount")} *</span>
            <input
              type="number"
              min="0"
              step={values.currency === "KHR" ? "1" : "0.01"}
              name="amount"
              value={values.amount}
              onChange={change}
              placeholder="0.00"
              required
            />
          </label>
          <label>
            <span>{t("Period start")}</span>
            <input
              type="date"
              name="period_start"
              value={values.period_start}
              onChange={change}
            />
          </label>
          <label>
            <span>{t("Period end")}</span>
            <input
              type="date"
              name="period_end"
              value={values.period_end}
              onChange={change}
            />
          </label>
          <label>
            <span>{t("Payment method")}</span>
            <select name="payment_method" value={values.payment_method} onChange={change}>
              <option value="cash">{t("Cash")}</option>
              <option value="bank">{t("Bank")}</option>
              <option value="other">{t("Other")}</option>
            </select>
          </label>
          <label>
            <span>{t("Reference number")}</span>
            <input
              name="reference_number"
              value={values.reference_number}
              onChange={change}
              placeholder={t("Receipt or payment reference")}
            />
          </label>
          <label className="full-width">
            <span>{t("Notes")}</span>
            <textarea
              rows="3"
              name="notes"
              value={values.notes}
              onChange={change}
              placeholder={t("Optional payout note...")}
            />
          </label>
        </div>
        <div className="modal-actions">
          <button type="button" className="secondary-button" onClick={onClose} disabled={busy}>
            {t("Cancel")}
          </button>
          <button
            type="submit"
            className="primary-button"
            disabled={busy || !values.user_id || !values.branch_id || Number(values.amount) <= 0}
          >
            {busy ? t("Saving...") : t("Record payout")}
          </button>
        </div>
      </form>
    </Modal>
  );
}

