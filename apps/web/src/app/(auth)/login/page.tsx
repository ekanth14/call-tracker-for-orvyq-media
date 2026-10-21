"use client";

import React, { useState } from "react";
import { useRouter } from "next/navigation";
import { createClient } from "@/lib/supabase/client";
import { PhoneCall, ShieldCheck, ArrowRight, Loader2, AlertCircle, Smartphone } from "lucide-react";

export default function LoginPage() {
  const router = useRouter();
  const [email, setEmail] = useState("");
  const [password, setPassword] = useState("");
  const [loading, setLoading] = useState(false);
  const [error, setError] = useState<string | null>(null);

  const handleLogin = async (e: React.FormEvent) => {
    e.preventDefault();
    setLoading(true);
    setError(null);

    try {
      const supabase = createClient();
      const { data, error: authError } = await supabase.auth.signInWithPassword({
        email,
        password,
      });

      if (authError) {
        setError(authError.message);
        setLoading(false);
        return;
      }

      if (data.user) {
        // Fetch user profile to determine destination
        const { data: profile, error: profileError } = await supabase
          .from("profiles")
          .select("role, is_active")
          .eq("id", data.user.id)
          .single();

        if (profileError || !profile) {
          setError("User profile record not found. Please contact the administrator.");
          setLoading(false);
          return;
        }

        // Callers are routed to the mobile-first /caller app
        if (profile.role === "caller") {
          router.push("/caller");
        } else {
          // Owners and managers are routed to the central management dashboard
          router.push("/");
        }
        router.refresh();
      }
    } catch (err: unknown) {
      setError(err instanceof Error ? err.message : "An unexpected error occurred.");
      setLoading(false);
    }
  };

  return (
    <div className="flex min-h-screen bg-slate-900 text-slate-100">
      {/* Left Brand Banner for Desktop */}
      <div className="hidden lg:flex lg:w-1/2 flex-col justify-between p-12 bg-gradient-to-br from-indigo-950 via-slate-900 to-slate-950 border-r border-slate-800">
        <div>
          <div className="flex items-center gap-3">
            <div className="h-10 w-10 rounded-xl bg-indigo-600 flex items-center justify-center text-white shadow-lg shadow-indigo-600/30">
              <PhoneCall className="h-5 w-5" />
            </div>
            <span className="text-xl font-bold tracking-tight text-white">Orvyqmedia</span>
          </div>
          <div className="mt-20">
            <span className="inline-flex items-center gap-1.5 px-3 py-1 rounded-full text-xs font-medium bg-indigo-500/10 text-indigo-400 border border-indigo-500/20">
              <ShieldCheck className="h-3.5 w-3.5" />
              Cold-Calling & Shift Accountability
            </span>
            <h1 className="mt-4 text-4xl font-extrabold tracking-tight text-white sm:text-5xl">
              Accountability for Cold-Calling.
            </h1>
            <p className="mt-4 text-base text-slate-400 max-w-md leading-relaxed">
              Real-time work shift verification, lead queue execution, verified talk time metrics, and unified team communications for iOS, Android, and Web.
            </p>
          </div>
        </div>

        <div className="flex items-center justify-between text-xs text-slate-500">
          <div>© 2026 Orvyqmedia. Internal Telecalling Platform.</div>
          <div className="flex items-center gap-1 text-slate-400">
            <Smartphone className="h-3.5 w-3.5 text-indigo-400" /> iOS & Android Ready
          </div>
        </div>
      </div>

      {/* Right Login Form */}
      <div className="flex flex-1 flex-col justify-center px-6 py-12 lg:px-16 xl:px-24">
        <div className="mx-auto w-full max-w-md">
          {/* Mobile Header */}
          <div className="lg:hidden flex items-center gap-3 mb-8">
            <div className="h-9 w-9 rounded-xl bg-indigo-600 flex items-center justify-center text-white shadow-md shadow-indigo-600/20">
              <PhoneCall className="h-5 w-5" />
            </div>
            <div>
              <div className="text-lg font-bold text-white leading-tight">Orvyqmedia</div>
              <div className="text-[11px] text-indigo-400 font-medium flex items-center gap-1">
                <Smartphone className="h-3 w-3" /> Web & iOS Calling Portal
              </div>
            </div>
          </div>

          <h2 className="text-2xl font-bold text-white tracking-tight">Welcome Back</h2>
          <p className="mt-1.5 text-sm text-slate-400">
            Sign in with your team or manager credentials to access the dialer and queue.
          </p>

          {error && (
            <div className="mt-6 flex items-start gap-3 p-4 rounded-xl bg-rose-500/10 border border-rose-500/20 text-rose-300 text-sm animate-in fade-in">
              <AlertCircle className="h-5 w-5 shrink-0 mt-0.5 text-rose-400" />
              <div>{error}</div>
            </div>
          )}

          <form onSubmit={handleLogin} className="mt-8 space-y-5">
            <div>
              <label className="block text-xs font-semibold uppercase tracking-wider text-slate-300 mb-2">
                Work Email
              </label>
              <input
                type="email"
                required
                value={email}
                onChange={(e) => setEmail(e.target.value)}
                placeholder="name@orvyqmedia.com"
                autoComplete="email"
                className="w-full px-4 py-3.5 rounded-xl bg-slate-800/80 border border-slate-700/80 text-white placeholder-slate-500 focus:outline-none focus:ring-2 focus:ring-indigo-500 focus:border-transparent transition-all text-sm"
              />
            </div>

            <div>
              <label className="block text-xs font-semibold uppercase tracking-wider text-slate-300 mb-2">
                Password
              </label>
              <input
                type="password"
                required
                value={password}
                onChange={(e) => setPassword(e.target.value)}
                placeholder="••••••••••••"
                autoComplete="current-password"
                className="w-full px-4 py-3.5 rounded-xl bg-slate-800/80 border border-slate-700/80 text-white placeholder-slate-500 focus:outline-none focus:ring-2 focus:ring-indigo-500 focus:border-transparent transition-all text-sm"
              />
            </div>

            <button
              type="submit"
              disabled={loading}
              className="w-full flex items-center justify-center gap-2 py-3.5 px-4 rounded-xl font-semibold text-sm text-white bg-indigo-600 hover:bg-indigo-500 active:bg-indigo-700 transition shadow-lg shadow-indigo-600/25 disabled:opacity-60 disabled:cursor-not-allowed"
            >
              {loading ? (
                <>
                  <Loader2 className="h-4 w-4 animate-spin" />
                  Authenticating...
                </>
              ) : (
                <>
                  Sign In & Enter Queue
                  <ArrowRight className="h-4 w-4" />
                </>
              )}
            </button>
          </form>

          <div className="mt-8 pt-6 border-t border-slate-800/80 text-center">
            <p className="text-xs text-slate-500">
              iPhone & iPad: Tap Safari Share &gt; <span className="text-slate-300 font-medium">Add to Home Screen</span> for the native app experience.
            </p>
          </div>
        </div>
      </div>
    </div>
  );
}
