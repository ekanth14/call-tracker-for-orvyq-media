"use client";

import React, { useEffect, useState, useMemo } from "react";
import { createClient } from "@/lib/supabase/client";
import { normalizePhoneE164 } from "@/lib/phone";
import Papa from "papaparse";
import {
  Upload,
  UserCheck,
  Search,
  Filter,
  Users,
  CheckSquare,
  Square,
  Phone,
  Building2,
  FileSpreadsheet,
  FileText,
  AlertCircle,
  CheckCircle2,
  Loader2,
  X,
  Split,
  ChevronDown,
  RefreshCw,
} from "lucide-react";

interface Caller {
  id: string;
  full_name: string;
  is_active: boolean;
}

interface LeadRow {
  id: string;
  phone_e164: string;
  name: string | null;
  company: string | null;
  notes: string | null;
  status: string;
  assigned_to: string | null;
  assigned_at: string | null;
  attempt_count: number;
  last_call_at: string | null;
  created_at: string;
}

export default function LeadsPage() {
  const [leads, setLeads] = useState<LeadRow[]>([]);
  const [callers, setCallers] = useState<Caller[]>([]);
  const [loading, setLoading] = useState(true);

  // Filters & Search
  const [search, setSearch] = useState("");
  const [statusFilter, setStatusFilter] = useState("all");
  const [callerFilter, setCallerFilter] = useState("all");

  // Selection
  const [selectedIds, setSelectedIds] = useState<string[]>([]);

  // Modals
  const [importModalOpen, setImportModalOpen] = useState(false);
  const [assignModalOpen, setAssignModalOpen] = useState(false);

  // Import State
  const [importTab, setImportTab] = useState<"csv" | "paste">("csv");
  const [batchName, setBatchName] = useState("");
  const [pasteText, setPasteText] = useState("");
  const [csvFile, setCsvFile] = useState<File | null>(null);
  const [parsedPreview, setParsedPreview] = useState<
    Array<{ phone_raw: string; phone_norm?: string; valid: boolean; name?: string; company?: string; notes?: string }>
  >([]);
  const [duplicateStrategy, setDuplicateStrategy] = useState<"skip" | "update" | "reject">("skip");
  const [importLoading, setImportLoading] = useState(false);
  const [importResult, setImportResult] = useState<{
    imported: number;
    skipped_duplicates: number;
    invalid_numbers: number;
  } | null>(null);
  const [importError, setImportError] = useState<string | null>(null);

  // Assignment State
  const [assignMode, setAssignMode] = useState<"single" | "even_split">("single");
  const [targetCallerId, setTargetCallerId] = useState<string>("");
  const [splitCallerIds, setSplitCallerIds] = useState<string[]>([]);
  const [assignLoading, setAssignLoading] = useState(false);

  const fetchLeadsAndCallers = async () => {
    setLoading(true);
    const supabase = createClient();

    const [{ data: leadsData, error: leadsErr }, { data: callersData, error: callersErr }] =
      await Promise.all([
        supabase.from("leads").select("*").order("created_at", { ascending: false }).limit(500),
        supabase.from("profiles").select("id, full_name, is_active").eq("role", "caller"),
      ]);

    if (!leadsErr && leadsData) {
      setLeads(leadsData);
    }
    if (!callersErr && callersData) {
      setCallers(callersData);
    }
    setLoading(false);
  };

  useEffect(() => {
    fetchLeadsAndCallers();
  }, []);

  // Filtered Leads
  const filteredLeads = useMemo(() => {
    return leads.filter((l) => {
      const matchesSearch =
        l.phone_e164.includes(search) ||
        (l.name && l.name.toLowerCase().includes(search.toLowerCase())) ||
        (l.company && l.company.toLowerCase().includes(search.toLowerCase()));

      const matchesStatus = statusFilter === "all" || l.status === statusFilter;
      const matchesCaller =
        callerFilter === "all" ||
        (callerFilter === "unassigned" ? !l.assigned_to : l.assigned_to === callerFilter);

      return matchesSearch && matchesStatus && matchesCaller;
    });
  }, [leads, search, statusFilter, callerFilter]);

  // Selection helpers
  const toggleSelectAll = () => {
    if (selectedIds.length === filteredLeads.length) {
      setSelectedIds([]);
    } else {
      setSelectedIds(filteredLeads.map((l) => l.id));
    }
  };

  const toggleSelect = (id: string) => {
    setSelectedIds((prev) =>
      prev.includes(id) ? prev.filter((i) => i !== id) : [...prev, id]
    );
  };

  // CSV Parsing
  const handleFileUpload = (e: React.ChangeEvent<HTMLInputElement>) => {
    const file = e.target.files?.[0];
    if (!file) return;
    setCsvFile(file);

    Papa.parse<Record<string, string>>(file, {
      header: true,
      skipEmptyLines: true,
      complete: (results) => {
        const rows = results.data.map((row) => {
          // Detect phone column name flexibly
          const phoneKey =
            Object.keys(row).find((k) =>
              /phone|mobile|number|contact/i.test(k)
            ) || Object.keys(row)[0];

          const nameKey = Object.keys(row).find((k) => /name|client/i.test(k));
          const compKey = Object.keys(row).find((k) => /company|org|business/i.test(k));
          const notesKey = Object.keys(row).find((k) => /notes|remarks/i.test(k));

          const rawPhone = row[phoneKey] || "";
          const norm = normalizePhoneE164(rawPhone);

          return {
            phone_raw: rawPhone,
            phone_norm: norm.e164,
            valid: norm.success,
            name: nameKey ? row[nameKey] : undefined,
            company: compKey ? row[compKey] : undefined,
            notes: notesKey ? row[notesKey] : undefined,
          };
        });

        setParsedPreview(rows);
      },
    });
  };

  // Paste Parsing
  const handlePasteChange = (text: string) => {
    setPasteText(text);
    if (!text.trim()) {
      setParsedPreview([]);
      return;
    }

    const lines = text.split(/\r?\n/).filter((l) => l.trim().length > 0);
    const rows = lines.map((line) => {
      // Check if comma or tab separated: phone, name, company, notes
      const parts = line.split(/[,\t]/).map((p) => p.trim());
      const rawPhone = parts[0] || "";
      const norm = normalizePhoneE164(rawPhone);

      return {
        phone_raw: rawPhone,
        phone_norm: norm.e164,
        valid: norm.success,
        name: parts[1] || undefined,
        company: parts[2] || undefined,
        notes: parts[3] || undefined,
      };
    });

    setParsedPreview(rows);
  };

  const handleImportSubmit = async () => {
    setImportLoading(true);
    setImportError(null);
    setImportResult(null);

    const payload = parsedPreview.map((p) => ({
      phone_raw: p.phone_raw,
      name: p.name,
      company: p.company,
      notes: p.notes,
    }));

    try {
      const res = await fetch("/api/leads/import", {
        method: "POST",
        headers: { "Content-Type": "application/json" },
        body: JSON.stringify({
          leads: payload,
          batch_name: batchName,
          duplicate_strategy: duplicateStrategy,
        }),
      });

      const data = await res.json();
      if (!res.ok) {
        throw new Error(data.error || "Import failed.");
      }

      setImportResult({
        imported: data.imported,
        skipped_duplicates: data.skipped_duplicates,
        invalid_numbers: data.invalid_numbers,
      });

      // Refresh list after 1s
      setTimeout(() => {
        fetchLeadsAndCallers();
      }, 800);
    } catch (err: unknown) {
      setImportError(err instanceof Error ? err.message : "Error during import.");
    } finally {
      setImportLoading(false);
    }
  };

  // Assignment Handler
  const handleAssignSubmit = async () => {
    setAssignLoading(true);
    try {
      if (assignMode === "single") {
        await fetch("/api/leads/assign", {
          method: "POST",
          headers: { "Content-Type": "application/json" },
          body: JSON.stringify({
            type: "bulk",
            lead_ids: selectedIds,
            caller_id: targetCallerId || null,
          }),
        });
      } else {
        // Even split
        await fetch("/api/leads/assign", {
          method: "POST",
          headers: { "Content-Type": "application/json" },
          body: JSON.stringify({
            type: "even_split",
            lead_ids: selectedIds.length > 0 ? selectedIds : undefined,
            caller_ids: splitCallerIds,
          }),
        });
      }

      setAssignModalOpen(false);
      setSelectedIds([]);
      fetchLeadsAndCallers();
    } catch (err) {
      console.error("Assignment error:", err);
    } finally {
      setAssignLoading(false);
    }
  };

  const handleInlineSingleAssign = async (leadId: string, callerId: string) => {
    try {
      await fetch("/api/leads/assign", {
        method: "POST",
        headers: { "Content-Type": "application/json" },
        body: JSON.stringify({
          type: "single",
          lead_id: leadId,
          caller_id: callerId || null,
        }),
      });
      setLeads((prev) =>
        prev.map((l) =>
          l.id === leadId
            ? {
                ...l,
                assigned_to: callerId || null,
                status: callerId ? "assigned" : "new",
              }
            : l
        )
      );
    } catch (err) {
      console.error("Inline assign error:", err);
    }
  };

  return (
    <div className="p-8 max-w-7xl mx-auto space-y-6">
      {/* Top Header */}
      <div className="flex flex-col sm:flex-row sm:items-center sm:justify-between gap-4">
        <div>
          <h1 className="text-2xl font-bold tracking-tight text-slate-900">
            Leads & Distribution
          </h1>
          <p className="mt-1 text-sm text-slate-500">
            Import client contact lists, normalize Indian mobile numbers (+91), and assign to callers.
          </p>
        </div>

        <div className="flex items-center gap-3">
          <button
            onClick={() => {
              setBatchName(`Import - ${new Date().toLocaleDateString("en-IN")}`);
              setParsedPreview([]);
              setPasteText("");
              setImportResult(null);
              setImportError(null);
              setImportModalOpen(true);
            }}
            className="inline-flex items-center gap-2 px-4 py-2.5 rounded-xl font-medium text-sm text-white bg-indigo-600 hover:bg-indigo-700 transition shadow-sm"
          >
            <Upload className="h-4 w-4" />
            Import Leads
          </button>
        </div>
      </div>

      {/* Control Bar */}
      <div className="bg-white p-4 rounded-2xl border border-slate-200/80 shadow-sm flex flex-col md:flex-row items-center gap-4 justify-between">
        {/* Search */}
        <div className="relative flex-1 w-full">
          <Search className="h-4 w-4 text-slate-400 absolute left-3 top-1/2 -translate-y-1/2" />
          <input
            type="text"
            placeholder="Search leads by phone, client name, or company..."
            value={search}
            onChange={(e) => setSearch(e.target.value)}
            className="w-full pl-9 pr-4 py-2 rounded-xl bg-slate-50 border border-slate-200 text-sm focus:outline-none focus:ring-2 focus:ring-indigo-500 focus:bg-white transition"
          />
        </div>

        {/* Filters */}
        <div className="flex items-center gap-3 w-full md:w-auto">
          {/* Status Filter */}
          <select
            value={statusFilter}
            onChange={(e) => setStatusFilter(e.target.value)}
            className="px-3 py-2 rounded-xl border border-slate-200 bg-slate-50 text-xs font-medium text-slate-700 focus:outline-none focus:ring-2 focus:ring-indigo-500"
          >
            <option value="all">All Statuses</option>
            <option value="new">New (Uncalled)</option>
            <option value="assigned">Assigned</option>
            <option value="in_progress">In Progress</option>
            <option value="interested">Interested</option>
            <option value="not_interested">Not Interested</option>
            <option value="follow_up">Follow Up</option>
            <option value="called">Called</option>
            <option value="do_not_call">Do Not Call (DNC)</option>
          </select>

          {/* Caller Filter */}
          <select
            value={callerFilter}
            onChange={(e) => setCallerFilter(e.target.value)}
            className="px-3 py-2 rounded-xl border border-slate-200 bg-slate-50 text-xs font-medium text-slate-700 focus:outline-none focus:ring-2 focus:ring-indigo-500"
          >
            <option value="all">All Callers</option>
            <option value="unassigned">Unassigned</option>
            {callers.map((c) => (
              <option key={c.id} value={c.id}>
                {c.full_name}
              </option>
            ))}
          </select>

          <button
            onClick={fetchLeadsAndCallers}
            title="Refresh list"
            className="p-2 rounded-xl border border-slate-200 text-slate-500 hover:text-slate-800 hover:bg-slate-50 transition"
          >
            <RefreshCw className="h-4 w-4" />
          </button>
        </div>
      </div>

      {/* Bulk Action Bar (when items selected) */}
      {selectedIds.length > 0 && (
        <div className="bg-indigo-900 text-white px-6 py-3 rounded-2xl shadow-lg flex items-center justify-between animate-in slide-in-from-top-2">
          <div className="flex items-center gap-3 text-sm">
            <span className="font-bold bg-indigo-700 px-2.5 py-0.5 rounded-full text-xs">
              {selectedIds.length}
            </span>
            <span>leads selected</span>
          </div>

          <div className="flex items-center gap-3">
            <button
              onClick={() => {
                setAssignMode("single");
                setTargetCallerId("");
                setAssignModalOpen(true);
              }}
              className="px-4 py-1.5 rounded-xl bg-white text-indigo-950 font-semibold text-xs hover:bg-slate-100 transition shadow-sm"
            >
              Assign to Caller
            </button>
            <button
              onClick={() => {
                setAssignMode("even_split");
                setSplitCallerIds(callers.filter((c) => c.is_active).map((c) => c.id));
                setAssignModalOpen(true);
              }}
              className="px-4 py-1.5 rounded-xl bg-indigo-800 text-white font-semibold text-xs hover:bg-indigo-700 transition border border-indigo-700 flex items-center gap-1.5"
            >
              <Split className="h-3.5 w-3.5" />
              Even Split
            </button>
            <button
              onClick={() => setSelectedIds([])}
              className="p-1 rounded-lg text-indigo-300 hover:text-white"
            >
              <X className="h-4 w-4" />
            </button>
          </div>
        </div>
      )}

      {/* Leads Table */}
      <div className="bg-white rounded-2xl border border-slate-200/80 shadow-sm overflow-hidden">
        {loading ? (
          <div className="p-12 text-center text-slate-500 flex flex-col items-center justify-center gap-3">
            <Loader2 className="h-6 w-6 animate-spin text-indigo-600" />
            <span className="text-sm">Loading lead pipeline...</span>
          </div>
        ) : filteredLeads.length === 0 ? (
          <div className="p-12 text-center text-slate-500">
            <Users className="h-8 w-8 mx-auto text-slate-300 mb-2" />
            <h3 className="font-semibold text-slate-700">No Leads Found</h3>
            <p className="text-xs text-slate-400 mt-1 max-w-sm mx-auto">
              Click &quot;Import Leads&quot; above to upload your first batch of numbers via CSV or quick paste.
            </p>
          </div>
        ) : (
          <div className="overflow-x-auto">
            <table className="w-full text-left border-collapse text-sm">
              <thead>
                <tr className="bg-slate-50/80 border-b border-slate-200 text-xs font-semibold text-slate-500 uppercase tracking-wider">
                  <th className="py-3.5 px-4 w-12 text-center">
                    <button onClick={toggleSelectAll} className="text-slate-400 hover:text-slate-600">
                      {selectedIds.length === filteredLeads.length && filteredLeads.length > 0 ? (
                        <CheckSquare className="h-4 w-4 text-indigo-600" />
                      ) : (
                        <Square className="h-4 w-4" />
                      )}
                    </button>
                  </th>
                  <th className="py-3.5 px-6">Phone Number</th>
                  <th className="py-3.5 px-6">Contact / Company</th>
                  <th className="py-3.5 px-6">Status</th>
                  <th className="py-3.5 px-6">Assigned Caller</th>
                  <th className="py-3.5 px-6 text-center">Attempts</th>
                </tr>
              </thead>
              <tbody className="divide-y divide-slate-100">
                {filteredLeads.map((lead) => {
                  const isSelected = selectedIds.includes(lead.id);
                  return (
                    <tr
                      key={lead.id}
                      className={`hover:bg-slate-50/60 transition ${
                        isSelected ? "bg-indigo-50/40" : ""
                      }`}
                    >
                      <td className="py-4 px-4 text-center">
                        <button
                          onClick={() => toggleSelect(lead.id)}
                          className="text-slate-400 hover:text-slate-600"
                        >
                          {isSelected ? (
                            <CheckSquare className="h-4 w-4 text-indigo-600" />
                          ) : (
                            <Square className="h-4 w-4" />
                          )}
                        </button>
                      </td>
                      <td className="py-4 px-6">
                        <span className="font-mono text-xs font-semibold text-slate-900 bg-slate-100 px-2.5 py-1 rounded-md">
                          {lead.phone_e164}
                        </span>
                      </td>
                      <td className="py-4 px-6">
                        <div className="font-medium text-slate-800">
                          {lead.name || <span className="text-slate-400 italic">No name</span>}
                        </div>
                        {lead.company && (
                          <div className="text-xs text-slate-500 flex items-center gap-1 mt-0.5">
                            <Building2 className="h-3 w-3 text-slate-400" />
                            {lead.company}
                          </div>
                        )}
                      </td>
                      <td className="py-4 px-6">
                        <span
                          className={`inline-block px-2.5 py-0.5 rounded-full text-xs font-medium ${
                            lead.status === "interested"
                              ? "bg-purple-50 text-purple-700 border border-purple-200"
                              : lead.status === "not_interested"
                              ? "bg-slate-100 text-slate-600 border border-slate-200"
                              : lead.status === "assigned"
                              ? "bg-emerald-50 text-emerald-700 border border-emerald-200"
                              : lead.status === "in_progress"
                              ? "bg-blue-50 text-blue-700 border border-blue-200"
                              : lead.status === "do_not_call"
                              ? "bg-rose-50 text-rose-700 border border-rose-200"
                              : "bg-amber-50 text-amber-700 border border-amber-200"
                          }`}
                        >
                          {lead.status.replace("_", " ")}
                        </span>
                      </td>
                      <td className="py-4 px-6">
                        <select
                          value={lead.assigned_to || ""}
                          onChange={(e) => handleInlineSingleAssign(lead.id, e.target.value)}
                          className="px-2.5 py-1 rounded-lg border border-slate-200 bg-white text-xs text-slate-700 font-medium focus:outline-none focus:ring-1 focus:ring-indigo-500"
                        >
                          <option value="">-- Unassigned --</option>
                          {callers.map((c) => (
                            <option key={c.id} value={c.id}>
                              {c.full_name} {!c.is_active ? "(Inactive)" : ""}
                            </option>
                          ))}
                        </select>
                      </td>
                      <td className="py-4 px-6 text-center">
                        <span className="font-mono text-xs text-slate-500">
                          {lead.attempt_count}
                        </span>
                      </td>
                    </tr>
                  );
                })}
              </tbody>
            </table>
          </div>
        )}
      </div>

      {/* Import Modal */}
      {importModalOpen && (
        <div className="fixed inset-0 z-50 flex items-center justify-center p-4 bg-slate-900/60 backdrop-blur-sm animate-in fade-in duration-200">
          <div className="bg-white rounded-2xl max-w-2xl w-full shadow-2xl border border-slate-200 overflow-hidden flex flex-col max-h-[90vh]">
            <div className="flex items-center justify-between p-6 border-b border-slate-100 bg-slate-50/50">
              <div className="flex items-center gap-2.5">
                <div className="p-2 rounded-xl bg-indigo-50 text-indigo-600">
                  <Upload className="h-5 w-5" />
                </div>
                <div>
                  <h3 className="text-base font-bold text-slate-900">Import Leads</h3>
                  <p className="text-xs text-slate-500">E.164 Normalization with India (+91) default</p>
                </div>
              </div>
              <button
                onClick={() => setImportModalOpen(false)}
                className="p-1 rounded-lg text-slate-400 hover:text-slate-600 hover:bg-slate-100 transition"
              >
                <X className="h-5 w-5" />
              </button>
            </div>

            <div className="p-6 space-y-5 overflow-y-auto flex-1">
              {importError && (
                <div className="p-3.5 rounded-xl bg-rose-50 border border-rose-200 text-rose-700 text-xs flex items-center gap-2">
                  <AlertCircle className="h-4 w-4 shrink-0" />
                  {importError}
                </div>
              )}

              {importResult && (
                <div className="p-4 rounded-xl bg-emerald-50 border border-emerald-200 text-emerald-800 text-xs space-y-1">
                  <div className="font-bold flex items-center gap-1.5 text-sm">
                    <CheckCircle2 className="h-4 w-4 text-emerald-600" />
                    Import Batch Successful!
                  </div>
                  <div>✅ Successfully added: <b>{importResult.imported}</b> leads</div>
                  <div>ℹ️ Skipped duplicates: <b>{importResult.skipped_duplicates}</b> leads</div>
                  {importResult.invalid_numbers > 0 && (
                    <div>⚠️ Invalid numbers skipped: <b>{importResult.invalid_numbers}</b></div>
                  )}
                </div>
              )}

              {/* Batch Name */}
              <div>
                <label className="block text-xs font-semibold text-slate-700 mb-1">
                  Batch Name
                </label>
                <input
                  type="text"
                  value={batchName}
                  onChange={(e) => setBatchName(e.target.value)}
                  placeholder="e.g. October Fashion Brands"
                  className="w-full px-3.5 py-2.5 rounded-xl border border-slate-200 text-sm focus:outline-none focus:ring-2 focus:ring-indigo-500"
                />
              </div>

              {/* Tabs: CSV vs Paste */}
              <div className="flex border-b border-slate-200">
                <button
                  type="button"
                  onClick={() => setImportTab("csv")}
                  className={`pb-3 px-4 font-semibold text-xs border-b-2 transition flex items-center gap-1.5 ${
                    importTab === "csv"
                      ? "border-indigo-600 text-indigo-600"
                      : "border-transparent text-slate-500 hover:text-slate-800"
                  }`}
                >
                  <FileSpreadsheet className="h-4 w-4" />
                  Upload CSV File
                </button>
                <button
                  type="button"
                  onClick={() => setImportTab("paste")}
                  className={`pb-3 px-4 font-semibold text-xs border-b-2 transition flex items-center gap-1.5 ${
                    importTab === "paste"
                      ? "border-indigo-600 text-indigo-600"
                      : "border-transparent text-slate-500 hover:text-slate-800"
                  }`}
                >
                  <FileText className="h-4 w-4" />
                  Paste Numbers / CSV Text
                </button>
              </div>

              {importTab === "csv" ? (
                <div className="border-2 border-dashed border-slate-200 rounded-2xl p-8 text-center bg-slate-50/50 hover:bg-slate-50 transition cursor-pointer">
                  <input
                    type="file"
                    accept=".csv"
                    onChange={handleFileUpload}
                    id="csv-file-input"
                    className="hidden"
                  />
                  <label htmlFor="csv-file-input" className="cursor-pointer">
                    <FileSpreadsheet className="h-10 w-10 mx-auto text-indigo-500 mb-2" />
                    <span className="font-semibold text-sm text-slate-800 block">
                      {csvFile ? csvFile.name : "Click to select CSV file"}
                    </span>
                    <span className="text-xs text-slate-400 mt-1 block">
                      Supports headers: phone, name, company, notes
                    </span>
                  </label>
                </div>
              ) : (
                <div>
                  <label className="block text-xs font-semibold text-slate-700 mb-1">
                    Paste lines (one per row):
                  </label>
                  <textarea
                    rows={6}
                    value={pasteText}
                    onChange={(e) => handlePasteChange(e.target.value)}
                    placeholder={"9876543210\n09876543211, Amit Sharma, TechCorp\n+91 98765 43212, Priya, Apex Agency"}
                    className="w-full px-3.5 py-2.5 rounded-xl border border-slate-200 text-xs font-mono focus:outline-none focus:ring-2 focus:ring-indigo-500"
                  />
                </div>
              )}

              {/* Duplicate Strategy */}
              <div>
                <label className="block text-xs font-semibold text-slate-700 mb-1">
                  Duplicate Phone Handling
                </label>
                <div className="grid grid-cols-3 gap-3">
                  {[
                    { key: "skip", label: "Skip Existing", desc: "Ignore numbers already present" },
                    { key: "update", label: "Update Notes", desc: "Update details on duplicate" },
                    { key: "reject", label: "Reject Import", desc: "Abort if duplicates found" },
                  ].map((s) => (
                    <button
                      key={s.key}
                      type="button"
                      onClick={() => setDuplicateStrategy(s.key as any)}
                      className={`p-3 rounded-xl border text-left transition ${
                        duplicateStrategy === s.key
                          ? "border-indigo-600 bg-indigo-50/50"
                          : "border-slate-200 hover:bg-slate-50"
                      }`}
                    >
                      <div className="text-xs font-bold text-slate-900">{s.label}</div>
                      <div className="text-[10px] text-slate-500 mt-0.5">{s.desc}</div>
                    </button>
                  ))}
                </div>
              </div>

              {/* Live Preview */}
              {parsedPreview.length > 0 && (
                <div>
                  <div className="flex items-center justify-between text-xs font-semibold text-slate-700 mb-2">
                    <span>Preview ({parsedPreview.length} rows parsed)</span>
                    <span className="text-emerald-600">
                      {parsedPreview.filter((p) => p.valid).length} valid numbers
                    </span>
                  </div>

                  <div className="max-h-40 overflow-y-auto rounded-xl border border-slate-200 divide-y divide-slate-100 text-xs">
                    {parsedPreview.slice(0, 15).map((p, idx) => (
                      <div key={idx} className="p-2.5 flex items-center justify-between">
                        <div className="font-mono">
                          <span className="text-slate-400 mr-2">{p.phone_raw}</span>
                          <span className="font-semibold text-indigo-600">{p.phone_norm || "INVALID"}</span>
                        </div>
                        <span
                          className={`px-2 py-0.5 rounded-full text-[10px] font-semibold ${
                            p.valid
                              ? "bg-emerald-50 text-emerald-700"
                              : "bg-rose-50 text-rose-700"
                          }`}
                        >
                          {p.valid ? "Normalized" : "Invalid"}
                        </span>
                      </div>
                    ))}
                    {parsedPreview.length > 15 && (
                      <div className="p-2 text-center text-[11px] text-slate-400 bg-slate-50">
                        ...and {parsedPreview.length - 15} more rows
                      </div>
                    )}
                  </div>
                </div>
              )}
            </div>

            <div className="p-4 border-t border-slate-100 bg-slate-50 flex items-center justify-end gap-3">
              <button
                type="button"
                onClick={() => setImportModalOpen(false)}
                className="px-4 py-2 rounded-xl text-xs font-semibold text-slate-600 hover:bg-slate-200/50 transition"
              >
                Close
              </button>
              <button
                type="button"
                disabled={importLoading || parsedPreview.length === 0}
                onClick={handleImportSubmit}
                className="px-5 py-2.5 rounded-xl text-xs font-semibold text-white bg-indigo-600 hover:bg-indigo-700 transition shadow-sm disabled:opacity-50 flex items-center gap-2"
              >
                {importLoading && <Loader2 className="h-3.5 w-3.5 animate-spin" />}
                Import {parsedPreview.filter((p) => p.valid).length} Leads
              </button>
            </div>
          </div>
        </div>
      )}

      {/* Assignment Modal */}
      {assignModalOpen && (
        <div className="fixed inset-0 z-50 flex items-center justify-center p-4 bg-slate-900/60 backdrop-blur-sm animate-in fade-in duration-200">
          <div className="bg-white rounded-2xl max-w-md w-full shadow-2xl border border-slate-200 overflow-hidden">
            <div className="flex items-center justify-between p-6 border-b border-slate-100 bg-slate-50/50">
              <div className="flex items-center gap-2.5">
                <div className="p-2 rounded-xl bg-indigo-50 text-indigo-600">
                  <UserCheck className="h-5 w-5" />
                </div>
                <div>
                  <h3 className="text-base font-bold text-slate-900">Assign Selected Leads</h3>
                  <p className="text-xs text-slate-500">
                    Distributing {selectedIds.length > 0 ? selectedIds.length : "pending"} leads
                  </p>
                </div>
              </div>
              <button
                onClick={() => setAssignModalOpen(false)}
                className="p-1 rounded-lg text-slate-400 hover:text-slate-600 hover:bg-slate-100 transition"
              >
                <X className="h-5 w-5" />
              </button>
            </div>

            <div className="p-6 space-y-4">
              {/* Assign Mode Tabs */}
              <div className="flex border-b border-slate-200">
                <button
                  type="button"
                  onClick={() => setAssignMode("single")}
                  className={`pb-2.5 px-4 font-semibold text-xs border-b-2 transition ${
                    assignMode === "single"
                      ? "border-indigo-600 text-indigo-600"
                      : "border-transparent text-slate-500"
                  }`}
                >
                  Single Caller
                </button>
                <button
                  type="button"
                  onClick={() => setAssignMode("even_split")}
                  className={`pb-2.5 px-4 font-semibold text-xs border-b-2 transition flex items-center gap-1.5 ${
                    assignMode === "even_split"
                      ? "border-indigo-600 text-indigo-600"
                      : "border-transparent text-slate-500"
                  }`}
                >
                  <Split className="h-3.5 w-3.5" />
                  Even Split Across Team
                </button>
              </div>

              {assignMode === "single" ? (
                <div>
                  <label className="block text-xs font-semibold text-slate-700 mb-2">
                    Choose Destination Caller:
                  </label>
                  <select
                    value={targetCallerId}
                    onChange={(e) => setTargetCallerId(e.target.value)}
                    className="w-full px-3.5 py-2.5 rounded-xl border border-slate-200 text-sm focus:outline-none focus:ring-2 focus:ring-indigo-500"
                  >
                    <option value="">-- Choose Caller --</option>
                    {callers.map((c) => (
                      <option key={c.id} value={c.id}>
                        {c.full_name} {!c.is_active ? "(Inactive)" : ""}
                      </option>
                    ))}
                  </select>
                </div>
              ) : (
                <div className="space-y-2">
                  <label className="block text-xs font-semibold text-slate-700">
                    Select Callers to Participate in Even Split:
                  </label>
                  <div className="max-h-48 overflow-y-auto border border-slate-200 rounded-xl divide-y divide-slate-100 text-xs">
                    {callers.map((c) => {
                      const isChecked = splitCallerIds.includes(c.id);
                      return (
                        <label
                          key={c.id}
                          className="flex items-center gap-3 p-3 hover:bg-slate-50 cursor-pointer"
                        >
                          <input
                            type="checkbox"
                            checked={isChecked}
                            onChange={() => {
                              setSplitCallerIds((prev) =>
                                prev.includes(c.id)
                                  ? prev.filter((id) => id !== c.id)
                                  : [...prev, c.id]
                              );
                            }}
                            className="rounded text-indigo-600 focus:ring-indigo-500 h-4 w-4"
                          />
                          <div>
                            <div className="font-semibold text-slate-900">{c.full_name}</div>
                            {!c.is_active && (
                              <div className="text-[10px] text-rose-500">Currently inactive</div>
                            )}
                          </div>
                        </label>
                      );
                    })}
                  </div>
                  <p className="text-[11px] text-slate-400">
                    Leads will be assigned equally in round-robin fashion across the {splitCallerIds.length} selected callers.
                  </p>
                </div>
              )}

              <div className="pt-4 border-t border-slate-100 flex items-center justify-end gap-3">
                <button
                  type="button"
                  onClick={() => setAssignModalOpen(false)}
                  className="px-4 py-2 rounded-xl text-xs font-semibold text-slate-600 hover:bg-slate-100 transition"
                >
                  Cancel
                </button>
                <button
                  type="button"
                  disabled={
                    assignLoading ||
                    (assignMode === "single" && !targetCallerId) ||
                    (assignMode === "even_split" && splitCallerIds.length === 0)
                  }
                  onClick={handleAssignSubmit}
                  className="px-5 py-2.5 rounded-xl text-xs font-semibold text-white bg-indigo-600 hover:bg-indigo-700 transition shadow-sm disabled:opacity-50 flex items-center gap-2"
                >
                  {assignLoading && <Loader2 className="h-3.5 w-3.5 animate-spin" />}
                  Confirm Assignment
                </button>
              </div>
            </div>
          </div>
        </div>
      )}
    </div>
  );
}
