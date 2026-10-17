"use client";

import React, { useEffect, useState } from "react";
import { createClient } from "@/lib/supabase/client";
import {
  BarChart3,
  TrendingUp,
  Download,
  Users,
  Clock,
  PhoneCall,
  CheckCircle2,
  XCircle,
  AlertTriangle,
  Award,
  RefreshCw,
  Loader2,
  PieChart,
} from "lucide-react";

interface CallerKPI {
  id: string;
  name: string;
  email: string;
  totalCalls: number;
  connectedCalls: number;
  totalTalkSecs: number;
  interestedCount: number;
  flagsCount: number;
}

interface ReasonCount {
  id: string;
  label: string;
  category: string;
  count: number;
  percentage: number;
}

export default function ReportsPage() {
  const [loading, setLoading] = useState(true);
  const [callerKpis, setCallerKpis] = useState<CallerKPI[]>([]);
  const [reasonCounts, setReasonCounts] = useState<ReasonCount[]>([]);
  const [totalCalls, setTotalCalls] = useState(0);
  const [connectedCalls, setConnectedCalls] = useState(0);
  const [totalTalkSecs, setTotalTalkSecs] = useState(0);
  const [interestedTotal, setInterestedTotal] = useState(0);

  const fetchReportData = async () => {
    setLoading(true);
    const supabase = createClient();

    // 1. Fetch Callers
    const { data: callers } = await supabase
      .from("profiles")
      .select("id, full_name, email")
      .eq("role", "caller");

    // 2. Fetch Calls with Dispositions and Flags
    const { data: calls } = await supabase
      .from("calls")
      .select(`
        id,
        caller_id,
        talk_secs,
        disposition:dispositions(connected, outcome, reason_ids),
        flags(id)
      `);

    // 3. Fetch Seed Reasons (§10.2)
    const { data: reasons } = await supabase
      .from("reasons")
      .select("id, label, category");

    if (calls && callers) {
      setTotalCalls(calls.length);

      let connCount = 0;
      let talkSecsAcc = 0;
      let interestedAcc = 0;

      // Map KPIs per caller
      const kpiMap: { [key: string]: CallerKPI } = {};
      callers.forEach((c) => {
        kpiMap[c.id] = {
          id: c.id,
          name: c.full_name || "Caller",
          email: c.email || "",
          totalCalls: 0,
          connectedCalls: 0,
          totalTalkSecs: 0,
          interestedCount: 0,
          flagsCount: 0,
        };
      });

      // Reason frequency map
      const reasonFreq: { [key: string]: number } = {};
      let totalNotInterestedDispositions = 0;

      calls.forEach((call: any) => {
        const caller = kpiMap[call.caller_id];
        const disp = Array.isArray(call.disposition)
          ? call.disposition[0]
          : call.disposition;
        const flagsList = call.flags || [];

        const isConn = disp?.connected ?? (call.talk_secs >= 10);
        if (isConn) connCount++;
        talkSecsAcc += call.talk_secs || 0;

        if (disp?.outcome === "interested") {
          interestedAcc++;
        }

        if (caller) {
          caller.totalCalls++;
          if (isConn) caller.connectedCalls++;
          caller.totalTalkSecs += call.talk_secs || 0;
          if (disp?.outcome === "interested") caller.interestedCount++;
          caller.flagsCount += flagsList.length;
        }

        if (disp?.outcome === "not_interested") {
          totalNotInterestedDispositions++;
          const rIds: string[] = disp.reason_ids || [];
          rIds.forEach((rid) => {
            reasonFreq[rid] = (reasonFreq[rid] || 0) + 1;
          });
        }
      });

      setConnectedCalls(connCount);
      setTotalTalkSecs(talkSecsAcc);
      setInterestedTotal(interestedAcc);
      setCallerKpis(Object.values(kpiMap));

      // Process reasons breakdown
      if (reasons) {
        const rList: ReasonCount[] = reasons.map((r) => {
          const count = reasonFreq[r.id] || 0;
          const percentage =
            totalNotInterestedDispositions > 0
              ? Math.round((count / totalNotInterestedDispositions) * 100)
              : 0;
          return {
            id: r.id,
            label: r.label,
            category: r.category,
            count,
            percentage,
          };
        });

        rList.sort((a, b) => b.count - a.count);
        setReasonCounts(rList);
      }
    }

    setLoading(false);
  };

  useEffect(() => {
    fetchReportData();
  }, []);

  const formatSecsToHours = (secs: number) => {
    const hrs = Math.floor(secs / 3600);
    const mins = Math.floor((secs % 3600) / 60);
    return `${hrs}h ${mins}m`;
  };

  const exportReasonsCSV = () => {
    const headers = ["Reason Label", "Category", "Selections", "Percentage"];
    const rows = reasonCounts.map((r) => [
      `"${r.label}"`,
      `"${r.category}"`,
      r.count,
      `"${r.percentage}%"`,
    ]);

    const csv = [headers.join(","), ...rows.map((r) => r.join(","))].join("\n");
    const blob = new Blob([csv], { type: "text/csv;charset=utf-8;" });
    const url = URL.createObjectURL(blob);
    const a = document.createElement("a");
    a.href = url;
    a.download = `orvyq_reasons_report_${new Date().toISOString().slice(0, 10)}.csv`;
    a.click();
  };

  const exportCallerKpiCSV = () => {
    const headers = [
      "Caller Name",
      "Email",
      "Total Calls",
      "Connected Calls (≥10s)",
      "Connection Rate",
      "Total Talk Time",
      "Interested Leads",
      "Audit Flags",
    ];
    const rows = callerKpis.map((c) => {
      const rate =
        c.totalCalls > 0
          ? `${Math.round((c.connectedCalls / c.totalCalls) * 100)}%`
          : "0%";
      return [
        `"${c.name}"`,
        `"${c.email}"`,
        c.totalCalls,
        c.connectedCalls,
        `"${rate}"`,
        `"${formatSecsToHours(c.totalTalkSecs)}"`,
        c.interestedCount,
        c.flagsCount,
      ];
    });

    const csv = [headers.join(","), ...rows.map((r) => r.join(","))].join("\n");
    const blob = new Blob([csv], { type: "text/csv;charset=utf-8;" });
    const url = URL.createObjectURL(blob);
    const a = document.createElement("a");
    a.href = url;
    a.download = `orvyq_caller_performance_${new Date().toISOString().slice(0, 10)}.csv`;
    a.click();
  };

  const overallConnectionRate =
    totalCalls > 0 ? Math.round((connectedCalls / totalCalls) * 100) : 0;
  const overallConversionRate =
    totalCalls > 0 ? Math.round((interestedTotal / totalCalls) * 100) : 0;

  return (
    <div className="p-8 max-w-7xl mx-auto space-y-8">
      {/* Header */}
      <div className="flex flex-col sm:flex-row sm:items-center sm:justify-between gap-4">
        <div>
          <h1 className="text-2xl font-bold tracking-tight text-slate-900">
            Analytics & Reasons Report
          </h1>
          <p className="mt-1 text-sm text-slate-500">
            Performance comparison, conversion benchmarks, and breakdown of lead rejection reasons (§10.2 & §11).
          </p>
        </div>

        <div className="flex items-center gap-3">
          <button
            onClick={exportReasonsCSV}
            className="inline-flex items-center gap-2 px-3.5 py-2 rounded-xl text-xs font-semibold text-slate-700 bg-white border border-slate-200 hover:bg-slate-50 transition shadow-sm"
          >
            <Download className="h-3.5 w-3.5" />
            Reasons CSV
          </button>
          <button
            onClick={exportCallerKpiCSV}
            className="inline-flex items-center gap-2 px-3.5 py-2 rounded-xl text-xs font-semibold text-white bg-slate-900 hover:bg-slate-800 transition shadow-sm"
          >
            <Download className="h-3.5 w-3.5" />
            Caller KPIs CSV
          </button>
          <button
            onClick={fetchReportData}
            className="p-2 text-slate-500 hover:text-slate-900 bg-white border border-slate-200 rounded-xl"
            title="Refresh"
          >
            <RefreshCw className="h-4 w-4" />
          </button>
        </div>
      </div>

      {loading ? (
        <div className="p-24 text-center text-slate-500 flex flex-col items-center justify-center gap-3">
          <Loader2 className="h-7 w-7 animate-spin text-indigo-600" />
          <span className="text-sm font-medium">Aggregating calling metrics...</span>
        </div>
      ) : (
        <>
          {/* Executive Overview Cards */}
          <div className="grid grid-cols-1 sm:grid-cols-2 lg:grid-cols-4 gap-5">
            <div className="bg-white p-6 rounded-2xl border border-slate-200/80 shadow-sm">
              <div className="flex items-center justify-between text-slate-500 text-xs font-semibold uppercase">
                <span>Verified Connection Rate</span>
                <TrendingUp className="h-4 w-4 text-emerald-500" />
              </div>
              <div className="mt-3 text-3xl font-extrabold text-emerald-600">
                {overallConnectionRate}%
              </div>
              <div className="text-xs text-slate-400 mt-1">
                {connectedCalls} of {totalCalls} calls lasted ≥10s
              </div>
            </div>

            <div className="bg-white p-6 rounded-2xl border border-slate-200/80 shadow-sm">
              <div className="flex items-center justify-between text-slate-500 text-xs font-semibold uppercase">
                <span>Total Talk Duration</span>
                <Clock className="h-4 w-4 text-indigo-500" />
              </div>
              <div className="mt-3 text-3xl font-extrabold text-slate-900">
                {formatSecsToHours(totalTalkSecs)}
              </div>
              <div className="text-xs text-slate-400 mt-1">
                Verified across all personal SIMs
              </div>
            </div>

            <div className="bg-white p-6 rounded-2xl border border-slate-200/80 shadow-sm">
              <div className="flex items-center justify-between text-slate-500 text-xs font-semibold uppercase">
                <span>Interested Leads</span>
                <CheckCircle2 className="h-4 w-4 text-purple-500" />
              </div>
              <div className="mt-3 text-3xl font-extrabold text-purple-600">
                {interestedTotal}
              </div>
              <div className="text-xs text-slate-400 mt-1">
                {overallConversionRate}% overall conversion rate
              </div>
            </div>

            <div className="bg-white p-6 rounded-2xl border border-slate-200/80 shadow-sm">
              <div className="flex items-center justify-between text-slate-500 text-xs font-semibold uppercase">
                <span>Active Callers</span>
                <Users className="h-4 w-4 text-blue-500" />
              </div>
              <div className="mt-3 text-3xl font-extrabold text-slate-900">
                {callerKpis.length}
              </div>
              <div className="text-xs text-slate-400 mt-1">
                Agents dialing assigned queues
              </div>
            </div>
          </div>

          {/* Section: Rejection Reasons Report (§10.2) */}
          <div className="bg-white p-6 rounded-2xl border border-slate-200/80 shadow-sm space-y-6">
            <div className="flex items-center justify-between">
              <div>
                <h3 className="text-base font-bold text-slate-900 flex items-center gap-2">
                  <PieChart className="h-5 w-5 text-indigo-600" />
                  Why Leads Are Not Interested (Reasons Breakdown)
                </h3>
                <p className="text-xs text-slate-400 mt-0.5">
                  Extracted from mandatory post-call dialogs submitted by callers on Android.
                </p>
              </div>
            </div>

            {reasonCounts.every((r) => r.count === 0) ? (
              <div className="p-8 text-center text-slate-400 text-xs bg-slate-50 rounded-xl">
                No "Not Interested" reasons recorded yet. As callers complete their post-call dialogs, objections will be ranked here.
              </div>
            ) : (
              <div className="space-y-4">
                {reasonCounts.map((reason) => (
                  <div key={reason.id} className="space-y-1.5">
                    <div className="flex items-center justify-between text-xs font-semibold">
                      <span className="text-slate-800">{reason.label}</span>
                      <span className="text-slate-500 font-mono">
                        {reason.count} times ({reason.percentage}%)
                      </span>
                    </div>
                    <div className="h-2.5 w-full bg-slate-100 rounded-full overflow-hidden">
                      <div
                        className="h-full bg-indigo-600 rounded-full transition-all duration-500"
                        style={{ width: `${Math.max(reason.percentage, 2)}%` }}
                      />
                    </div>
                  </div>
                ))}
              </div>
            )}
          </div>

          {/* Section: Caller Performance Comparison Leaderboard */}
          <div className="bg-white rounded-2xl border border-slate-200/80 shadow-sm overflow-hidden">
            <div className="p-6 border-b border-slate-100 flex items-center justify-between">
              <div>
                <h3 className="text-base font-bold text-slate-900 flex items-center gap-2">
                  <Award className="h-5 w-5 text-amber-500" />
                  Caller Performance Leaderboard
                </h3>
                <p className="text-xs text-slate-400 mt-0.5">
                  Side-by-side audit of calls placed, verified connected rate, talk time, and flag anomalies.
                </p>
              </div>
            </div>

            <div className="overflow-x-auto">
              <table className="w-full text-left border-collapse text-sm">
                <thead>
                  <tr className="bg-slate-50/80 border-b border-slate-200 text-xs font-semibold text-slate-500 uppercase tracking-wider">
                    <th className="py-3.5 px-6">Caller</th>
                    <th className="py-3.5 px-6">Total Dials</th>
                    <th className="py-3.5 px-6">Connected (≥10s)</th>
                    <th className="py-3.5 px-6">Connection Rate</th>
                    <th className="py-3.5 px-6">Total Talk Time</th>
                    <th className="py-3.5 px-6">Interested Leads</th>
                    <th className="py-3.5 px-6 text-right">Flags</th>
                  </tr>
                </thead>
                <tbody className="divide-y divide-slate-100">
                  {callerKpis.map((kpi, idx) => {
                    const connRate =
                      kpi.totalCalls > 0
                        ? Math.round((kpi.connectedCalls / kpi.totalCalls) * 100)
                        : 0;

                    return (
                      <tr key={kpi.id} className="hover:bg-slate-50/60 transition">
                        <td className="py-4 px-6">
                          <div className="flex items-center gap-3">
                            <div className="h-8 w-8 rounded-full bg-slate-100 text-slate-600 flex items-center justify-center font-bold text-xs">
                              {idx + 1}
                            </div>
                            <div>
                              <div className="font-semibold text-slate-900">
                                {kpi.name}
                              </div>
                              <div className="text-xs text-slate-400">
                                {kpi.email}
                              </div>
                            </div>
                          </div>
                        </td>
                        <td className="py-4 px-6 font-mono text-xs font-semibold text-slate-800">
                          {kpi.totalCalls}
                        </td>
                        <td className="py-4 px-6 font-mono text-xs text-emerald-600 font-semibold">
                          {kpi.connectedCalls}
                        </td>
                        <td className="py-4 px-6">
                          <span
                            className={`inline-block px-2.5 py-0.5 rounded-full text-xs font-bold ${
                              connRate >= 60
                                ? "bg-emerald-50 text-emerald-700 border border-emerald-200"
                                : connRate >= 30
                                ? "bg-amber-50 text-amber-700 border border-amber-200"
                                : "bg-slate-100 text-slate-500 border border-slate-200"
                            }`}
                          >
                            {connRate}%
                          </span>
                        </td>
                        <td className="py-4 px-6 font-mono text-xs text-slate-700">
                          {formatSecsToHours(kpi.totalTalkSecs)}
                        </td>
                        <td className="py-4 px-6 font-mono text-xs font-bold text-purple-600">
                          {kpi.interestedCount}
                        </td>
                        <td className="py-4 px-6 text-right">
                          {kpi.flagsCount > 0 ? (
                            <span className="inline-flex items-center gap-1 text-xs font-bold text-rose-600 bg-rose-50 px-2 py-0.5 rounded-md border border-rose-200">
                              <AlertTriangle className="h-3 w-3" />
                              {kpi.flagsCount}
                            </span>
                          ) : (
                            <span className="text-xs text-emerald-600 font-medium">0 Clean</span>
                          )}
                        </td>
                      </tr>
                    );
                  })}
                </tbody>
              </table>
            </div>
          </div>
        </>
      )}
    </div>
  );
}
