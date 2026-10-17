import type { Metadata } from "next";
import "./globals.css";

export const metadata: Metadata = {
  title: "Orvyqmedia Call Tracker",
  description: "Cold-Calling Tracker & Call-Log Verification Dashboard for Orvyqmedia",
};

export default function RootLayout({
  children,
}: Readonly<{
  children: React.ReactNode;
}>) {
  return (
    <html lang="en">
      <body className="min-h-screen bg-slate-50 text-slate-900 antialiased">
        {children}
      </body>
    </html>
  );
}
