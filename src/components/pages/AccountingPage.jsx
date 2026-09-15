import { BookOpenCheck, Download, FilePlus2, Pencil, Plus, RefreshCw, RotateCcw, Settings2 } from "lucide-react";
import { useCallback, useEffect, useMemo, useState } from "react";
import { useAuth } from "../context/AuthContext";
import { useLanguage } from "../context/LanguageContext";
import AccountingAccountModal from "../components/AccountingAccountModal";
import AccountingMappingModal from "../components/AccountingMappingModal";
import ManualJournalModal from "../components/ManualJournalModal";
import AccountingPeriodModal from "../components/AccountingPeriodModal";
import DateRangePresetFields from "../components/DateRangePresetFields";
import {
  accountingDate, accountingMoney, downloadAccountingCsv, isoDate, loadAccountingReport,
  loadAccountingWorkspace, saveAccountingAccount, saveAccountingMapping,
  saveManualJournal, setAccountingPeriodStatus, voidManualJournal
} from "../lib/accounting";

const EMPTY_REPORT = { summary: [], trial_balance: [], profit_loss: [], ledger: [] };

export default function AccountingPage() {
  const { supabase, profile, can } = useAuth();
  const { t, language } = useLanguage();
  const today = useMemo(() => isoDate(), []);
  const [filters, setFilters] = useState({ date_from: today, date_to: today, branch_id: "" });
  const [workspace, setWorkspace] = useState({ accounts: [], mappings: [], branches: [], periods: [], journals: [], can_manage: false, can_export: false });
  const [report, setReport] = useState(EMPTY_REPORT);
  const [tab, setTab] = useState("overview");
  const [loading, setLoading] = useState(true);
  const [busy, setBusy] = useState("");
  const [message, setMessage] = useState("");
  const [messageType, setMessageType] = useState("success");
  const [account, setAccount] = useState(undefined);
  const [mapping, setMapping] = useState(undefined);
  const [journal, setJournal] = useState(undefined);
  const [periodOpen, setPeriodOpen] = useState(false);

  const canManage = Boolean(workspace.can_manage || can("accounting.manage"));
  const canExport = Boolean(workspace.can_export || can("accounting.export"));

  const refresh = useCallback(async () => {
    if (!supabase || !profile?.id) return;
    try {
      setLoading(true);
      const [nextWorkspace, nextReport] = await Promise.all([
        loadAccountingWorkspace(supabase), loadAccountingReport(supabase, filters)
      ]);
      setWorkspace(nextWorkspace);
      setReport({ ...EMPTY_REPORT, ...nextReport });
    } catch (error) {
      setMessageType("error"); setMessage(error.message);
    } finally { setLoading(false); }
  }, [supabase, profile?.id, filters]);

  useEffect(() => { refresh(); }, [refresh]);
  function announce(type, text) { setMessageType(type); setMessage(text); }

  async function saveAccount(values) {
    try { setBusy("account"); await saveAccountingAccount(supabase, values); setAccount(undefined); announce("success", t("Accounting account saved.")); await refresh(); }
    catch (error) { announce("error", error.message); } finally { setBusy(""); }
  }
  async function saveMapping(values) {
    try { setBusy("mapping"); await saveAccountingMapping(supabase, values); setMapping(undefined); announce("success", t("Accounting mapping saved.")); await refresh(); }
    catch (error) { announce("error", error.message); } finally { setBusy(""); }
  }
  async function postJournal(values) {
    try { setBusy("journal"); await saveManualJournal(supabase, values); setJournal(undefined); announce("success", t("Balanced journal posted.")); await refresh(); }
    catch (error) { announce("error", error.message); } finally { setBusy(""); }
  }
  async function voidJournal(row) {
    const reason = window.prompt(t("Reason for voiding this journal:"));
    if (!reason) return;
    try { setBusy(row.id); await voidManualJournal(supabase, row.id, reason); announce("success", t("Journal voided.")); await refresh(); }
    catch (error) { announce("error", error.message); } finally { setBusy(""); }
  }
  async function savePeriod(values) {
    try { setBusy("period"); await setAccountingPeriodStatus(supabase, values); setPeriodOpen(false); announce("success", values.status === "closed" ? t("Accounting period closed.") : t("Accounting period reopened.")); await refresh(); }
    catch (error) { announce("error", error.message); } finally { setBusy(""); }
  }

  const summaryByCurrency = Object.fromEntries((report.summary || []).map((row) => [row.currency, row]));
  function exportLedger() {
    downloadAccountingCsv(`tiny-pos-general-ledger-${filters.date_from}-to-${filters.date_to}.csv`, [
      { label: "Date", value: "entry_date" }, { label: "Branch", value: "branch_name" }, { label: "Currency", value: "currency" },
      { label: "Source Type", value: "source_type" }, { label: "Source Number", value: "source_number" }, { label: "Description", value: "description" },
      { label: "Account Code", value: "account_code" }, { label: "Account Name", value: "account_name" }, { label: "Debit", value: "debit" }, { label: "Credit", value: "credit" }
    ], report.ledger || []);
  }
  function exportTrial() {
    downloadAccountingCsv(`tiny-pos-trial-balance-${filters.date_to}.csv`, [
      { label: "Currency", value: "currency" }, { label: "Account Code", value: "account_code" }, { label: "Account Name", value: "account_name" },
      { label: "Type", value: "account_type" }, { label: "Debit", value: "debit" }, { label: "Credit", value: "credit" }, { label: "Balance", value: "balance" }
    ], report.trial_balance || []);
  }

  return <div className="page-stack accounting-page">
    <div className="page-heading"><div><p className="eyebrow">{t("ACCOUNTING & EXPORT")}</p><h1>{t("Accounting Center")}</h1><p className="muted">{t("Generate a double-entry ledger from POS activity, post balanced adjustments and export separate USD and KHR accounting records.")}</p></div><div className="page-heading-actions">{canManage && <button type="button" className="primary-button" onClick={() => setJournal(null)}><FilePlus2 size={18} />{t("New journal")}</button>}<button type="button" className="secondary-button" onClick={refresh} disabled={loading}><RefreshCw size={18} className={loading ? "spin" : ""} />{t("Refresh")}</button></div></div>
    {message && <div className={`notice ${messageType}`}>{message}</div>}

    <section className="panel accounting-filter-panel"><div className="accounting-filters"><DateRangePresetFields from={filters.date_from} to={filters.date_to} onChange={(range) => setFilters((current) => ({ ...current, date_from: range.from, date_to: range.to }))} /><label className="accounting-branch-field"><span>{t("Branch")}</span><select value={filters.branch_id} onChange={(e) => setFilters((current) => ({ ...current, branch_id: e.target.value }))}><option value="">{workspace.all_branches ? t("All branches") : t("Current branch")}</option>{workspace.branches.map((b) => <option key={b.id} value={b.id}>{b.name}</option>)}</select></label></div></section>

    <div className="accounting-tabs" role="tablist">{[["overview", t("Overview")], ["trial", t("Trial Balance")], ["ledger", t("General Ledger")], ["accounts", t("Accounts & Mappings")], ["journals", t("Manual Journals")], ["periods", t("Periods")]].filter(([key]) => canManage || !["accounts", "journals", "periods"].includes(key)).map(([key, label]) => <button type="button" key={key} className={tab === key ? "active" : ""} onClick={() => setTab(key)}>{label}</button>)}</div>

    {tab === "overview" && <>
      <div className="accounting-currency-grid">{["USD", "KHR"].map((currency) => { const row = summaryByCurrency[currency] || {}; const equityTotal = Number(row.equity || 0) + Number(row.current_earnings || 0); return <section className="panel" key={currency}><div className="panel-title-row"><div><p className="eyebrow">{currency} {t("ACTIVITY")}</p><h2>{currency} {t("financial summary")}</h2></div><BookOpenCheck size={24} /></div><div className="accounting-summary-grid"><div><span title={t("Revenue")}>{t("Revenue")}</span><strong title={accountingMoney(row.revenue, currency)}>{accountingMoney(row.revenue, currency)}</strong></div><div><span title={t("Expenses")}>{t("Expenses")}</span><strong title={accountingMoney(row.expenses, currency)}>{accountingMoney(row.expenses, currency)}</strong></div><div className="highlight"><span title={t("Net profit")}>{t("Net profit")}</span><strong title={accountingMoney(row.net_profit, currency)}>{accountingMoney(row.net_profit, currency)}</strong></div><div><span title={t("Assets")}>{t("Assets")}</span><strong title={accountingMoney(row.assets, currency)}>{accountingMoney(row.assets, currency)}</strong></div><div><span title={t("Liabilities")}>{t("Liabilities")}</span><strong title={accountingMoney(row.liabilities, currency)}>{accountingMoney(row.liabilities, currency)}</strong></div><div><span title={t("Equity + earnings")}>{t("Equity + earnings")}</span><strong title={accountingMoney(equityTotal, currency)}>{accountingMoney(equityTotal, currency)}</strong></div></div></section>; })}</div>
      <section className="panel"><div className="panel-title-row"><div><p className="eyebrow">{t("PROFIT & LOSS")}</p><h2>{t("Period account activity")}</h2></div>{canExport && <button type="button" className="secondary-button" onClick={exportLedger}><Download size={18} />{t("Export ledger")}</button>}</div><div className="responsive-table"><table><thead><tr><th>{t("Currency")}</th><th>{t("Code")}</th><th>{t("Account")}</th><th>{t("Type")}</th><th>{t("Amount")}</th></tr></thead><tbody>{(report.profit_loss || []).map((row) => <tr key={`${row.account_id}-${row.currency}`}><td>{row.currency}</td><td>{row.account_code}</td><td><strong>{t(row.account_name)}</strong></td><td><span className={`status-pill ${row.account_type}`}>{t(row.account_type)}</span></td><td><strong>{accountingMoney(row.amount, row.currency)}</strong></td></tr>)}{!report.profit_loss?.length && <tr><td colSpan="5" className="empty-table">{t("No accounting activity in this period.")}</td></tr>}</tbody></table></div></section>
    </>}

    {tab === "trial" && <section className="panel"><div className="panel-title-row"><div><p className="eyebrow">{t("AS OF")} {filters.date_to}</p><h2>{t("Trial balance")}</h2></div>{canExport && <button type="button" className="secondary-button" onClick={exportTrial}><Download size={18} />{t("Export CSV")}</button>}</div><div className="responsive-table"><table><thead><tr><th>{t("Currency")}</th><th>{t("Code")}</th><th>{t("Account")}</th><th>{t("Type")}</th><th>{t("Debit")}</th><th>{t("Credit")}</th><th>{t("Normal balance")}</th></tr></thead><tbody>{(report.trial_balance || []).map((row) => <tr key={`${row.account_id}-${row.currency}`}><td>{row.currency}</td><td>{row.account_code}</td><td><strong>{t(row.account_name)}</strong></td><td>{t(row.account_type)}</td><td>{accountingMoney(row.debit, row.currency)}</td><td>{accountingMoney(row.credit, row.currency)}</td><td><strong>{accountingMoney(row.balance, row.currency)}</strong></td></tr>)}{!report.trial_balance?.length && <tr><td colSpan="7" className="empty-table">{t("No trial-balance activity yet.")}</td></tr>}</tbody></table></div></section>}

    {tab === "ledger" && <section className="panel"><div className="panel-title-row"><div><p className="eyebrow">{t("DOUBLE ENTRY")}</p><h2>{t("General ledger")}</h2></div>{canExport && <button type="button" className="secondary-button" onClick={exportLedger}><Download size={18} />{t("Export CSV")}</button>}</div><div className="responsive-table"><table><thead><tr><th>{t("Date")}</th><th>{t("Source")}</th><th>{t("Branch")}</th><th>{t("Account")}</th><th>{t("Description")}</th><th>{t("Debit")}</th><th>{t("Credit")}</th></tr></thead><tbody>{(report.ledger || []).map((row, index) => <tr key={`${row.source_type}-${row.source_id}-${row.account_id}-${index}`}><td>{accountingDate(row.entry_date, language)}</td><td><strong>{row.source_number}</strong><small>{t(row.source_type.replaceAll("_", " "))}</small></td><td>{row.branch_name || t("All branches")}</td><td>{row.account_code}<small>{t(row.account_name)}</small></td><td>{t(row.description)}</td><td>{Number(row.debit) ? accountingMoney(row.debit, row.currency) : "—"}</td><td>{Number(row.credit) ? accountingMoney(row.credit, row.currency) : "—"}</td></tr>)}{!report.ledger?.length && <tr><td colSpan="7" className="empty-table">{t("No ledger lines in this period.")}</td></tr>}</tbody></table></div></section>}

    {tab === "accounts" && canManage && <div className="accounting-admin-grid"><section className="panel"><div className="panel-title-row"><div><p className="eyebrow">{t("CHART OF ACCOUNTS")}</p><h2>{t("Accounts")}</h2></div><button type="button" className="primary-button" onClick={() => setAccount(null)}><Plus size={18} />{t("New account")}</button></div><div className="account-list">{workspace.accounts.map((row) => <button type="button" className="account-row" key={row.id} onClick={() => setAccount(row)}><span><strong>{row.code} — {t(row.name)}</strong><small>{t(row.account_type)} · {t(`normal ${row.normal_balance}`)}{row.is_system ? ` · ${t("system")}` : ""}</small></span><span className={`status-pill ${row.is_active ? "active" : "inactive"}`}>{row.is_active ? t("Active") : t("Inactive")}</span></button>)}</div></section><section className="panel"><div className="panel-title-row"><div><p className="eyebrow">{t("POSTING RULES")}</p><h2>{t("Operational mappings")}</h2></div><Settings2 size={23} /></div><div className="mapping-list">{workspace.mappings.map((row) => <button type="button" className="mapping-row" key={row.id} onClick={() => setMapping(row)}><span><strong>{t(row.mapping_key.replaceAll("_", " "))}</strong><small>{t(row.description || "Automatic posting mapping")}</small></span><span>{row.account_code}<small>{t(row.account_name)}</small></span></button>)}</div></section></div>}

    {tab === "journals" && canManage && <section className="panel"><div className="panel-title-row"><div><p className="eyebrow">{t("MANUAL POSTINGS")}</p><h2>{t("Manual journals")}</h2></div><button type="button" className="primary-button" onClick={() => setJournal(null)}><Plus size={18} />{t("New journal")}</button></div><div className="responsive-table"><table><thead><tr><th>{t("Date")}</th><th>{t("Journal")}</th><th>{t("Branch")}</th><th>{t("Currency")}</th><th>{t("Description")}</th><th>{t("Debit / Credit")}</th><th>{t("Status")}</th><th /></tr></thead><tbody>{workspace.journals.map((row) => { const total = (row.lines || []).reduce((sum, line) => sum + Number(line.debit || 0), 0); return <tr key={row.id}><td>{accountingDate(row.entry_date, language)}</td><td><strong>{row.journal_number}</strong><small>{t(row.source_type)}</small></td><td>{row.branch_name}</td><td>{row.currency}</td><td>{t(row.description)}<small>{row.reference_number || "—"}</small></td><td>{accountingMoney(total, row.currency)}</td><td><span className={`status-pill ${row.status}`}>{t(row.status)}</span></td><td><div className="table-actions">{row.status === "posted" && <><button type="button" className="icon-button" onClick={() => setJournal(row)} title={t("Edit")}><Pencil size={17} /></button><button type="button" className="icon-button danger" disabled={busy === row.id} onClick={() => voidJournal(row)} title={t("Void")}><RotateCcw size={17} /></button></>}</div></td></tr>; })}{!workspace.journals.length && <tr><td colSpan="8" className="empty-table">{t("No manual journals yet.")}</td></tr>}</tbody></table></div></section>}

    {tab === "periods" && canManage && <section className="panel"><div className="panel-title-row"><div><p className="eyebrow">{t("PERIOD CONTROL")}</p><h2>{t("Accounting periods")}</h2></div><button type="button" className="primary-button" onClick={() => setPeriodOpen(true)}><Plus size={18} />{t("Set period status")}</button></div><div className="responsive-table"><table><thead><tr><th>{t("Period")}</th><th>{t("Scope")}</th><th>{t("Status")}</th><th>{t("Closed at")}</th><th>{t("Notes")}</th></tr></thead><tbody>{workspace.periods.map((row) => <tr key={row.id}><td>{accountingDate(row.period_start, language)} → {accountingDate(row.period_end, language)}</td><td>{row.branch_name || t("All branches")}</td><td><span className={`status-pill ${row.status}`}>{t(row.status)}</span></td><td>{row.closed_at ? new Intl.DateTimeFormat(language === "km" ? "km-KH" : "en-US", { dateStyle: "medium", timeStyle: "short" }).format(new Date(row.closed_at)) : "—"}</td><td>{row.notes ? t(row.notes) : "—"}</td></tr>)}{!workspace.periods.length && <tr><td colSpan="5" className="empty-table">{t("No accounting periods have been closed.")}</td></tr>}</tbody></table></div></section>}

    {account !== undefined && <AccountingAccountModal account={account} busy={busy === "account"} onClose={() => setAccount(undefined)} onSave={saveAccount} />}
    {mapping !== undefined && <AccountingMappingModal mapping={mapping} accounts={workspace.accounts} busy={busy === "mapping"} onClose={() => setMapping(undefined)} onSave={saveMapping} />}
    {journal !== undefined && <ManualJournalModal journal={journal} accounts={workspace.accounts} branches={workspace.branches} defaultBranchId={profile?.branch_id} busy={busy === "journal"} onClose={() => setJournal(undefined)} onSave={postJournal} />}
    {periodOpen && <AccountingPeriodModal branches={workspace.branches} busy={busy === "period"} onClose={() => setPeriodOpen(false)} onSave={savePeriod} />}
  </div>;
}

