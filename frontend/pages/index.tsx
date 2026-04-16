"use client";

import Link from "next/link";
import {
  SignInButton,
  SignedIn,
  SignedOut,
  UserButton,
} from "@clerk/nextjs";

export default function Home() {
  return (
    <main className="min-h-screen bg-gradient-to-br from-white via-gray-50 to-gray-100 dark:from-gray-950 dark:via-gray-900 dark:to-gray-800">
      <div className="max-w-6xl mx-auto px-6 py-10">

        {/* NAVBAR */}
        <nav className="flex justify-between items-center mb-16">
          <h1 className="text-xl font-semibold tracking-tight text-gray-800 dark:text-gray-200">
            Healthcare SaaS App
          </h1>

          <div>
            <SignedOut>
              <SignInButton mode="modal">
                <button className="px-5 py-2 rounded-lg bg-gray-900 text-white dark:bg-white dark:text-black hover:opacity-90 transition">
                  Sign In
                </button>
              </SignInButton>
            </SignedOut>

            <SignedIn>
              <div className="flex items-center gap-4">
                <Link
                  href="/product"
                  className="px-5 py-2 rounded-lg bg-blue-600 text-white hover:bg-blue-700 transition"
                >
                  Dashboard
                </Link>
                <UserButton />
              </div>
            </SignedIn>
          </div>
        </nav>

        {/* HERO */}
        <section className="text-center mb-20">
          <h2 className="text-5xl md:text-6xl font-bold leading-tight tracking-tight mb-6">
            Turn Consultation Notes into{" "}
            <span className="bg-gradient-to-r from-blue-600 to-indigo-500 bg-clip-text text-transparent">
              Actionable Insights
            </span>
          </h2>

          <p className="text-lg md:text-xl text-gray-600 dark:text-gray-400 max-w-2xl mx-auto mb-10">
            AI-powered assistant that transforms raw medical notes into
            structured summaries, action plans, and patient-ready communication.
          </p>

          <SignedOut>
            <SignInButton mode="modal">
              <button className="px-8 py-4 rounded-xl bg-gradient-to-r from-blue-600 to-indigo-600 text-white text-lg font-semibold shadow-lg hover:shadow-xl hover:scale-105 transition">
                Start Free Trial
              </button>
            </SignInButton>
          </SignedOut>

          <SignedIn>
            <Link href="/product">
              <button className="px-8 py-4 rounded-xl bg-gradient-to-r from-blue-600 to-indigo-600 text-white text-lg font-semibold shadow-lg hover:shadow-xl hover:scale-105 transition">
                Open App
              </button>
            </Link>
          </SignedIn>
        </section>

        {/* FEATURES */}
        <section className="grid md:grid-cols-3 gap-8 mb-20">
          {[
            {
              icon: "📋",
              title: "Smart Summaries",
              desc: "Convert raw notes into structured, professional medical summaries instantly.",
            },
            {
              icon: "✅",
              title: "Action Plans",
              desc: "Automatically extract next steps and follow-up tasks from consultations.",
            },
            {
              icon: "📧",
              title: "Patient Communication",
              desc: "Generate clear, patient-friendly emails and instructions effortlessly.",
            },
          ].map((f, i) => (
            <div
              key={i}
              className="group p-6 rounded-2xl bg-white/70 dark:bg-gray-900/60 backdrop-blur border border-gray-200 dark:border-gray-800 shadow-sm hover:shadow-xl transition-all hover:-translate-y-1"
            >
              <div className="text-3xl mb-4">{f.icon}</div>
              <h3 className="text-lg font-semibold mb-2 text-gray-900 dark:text-gray-100">
                {f.title}
              </h3>
              <p className="text-gray-600 dark:text-gray-400 text-sm">
                {f.desc}
              </p>
            </div>
          ))}
        </section>

        {/* CTA SECTION */}
        <section className="text-center py-12 rounded-2xl bg-gradient-to-r from-blue-600 to-indigo-600 text-white shadow-lg">
          <h3 className="text-2xl font-semibold mb-4">
            Start saving hours on documentation
          </h3>
          <p className="mb-6 text-white/80">
            Join professionals using AI to streamline consultations.
          </p>

          <SignedOut>
            <SignInButton mode="modal">
              <button className="bg-white text-blue-600 px-6 py-3 rounded-lg font-semibold hover:scale-105 transition">
                Get Started
              </button>
            </SignInButton>
          </SignedOut>

          <SignedIn>
            <Link href="/product">
              <button className="bg-white text-blue-600 px-6 py-3 rounded-lg font-semibold hover:scale-105 transition">
                Go to Dashboard
              </button>
            </Link>
          </SignedIn>
        </section>

        {/* FOOTER */}
        <footer className="text-center mt-16 text-sm text-gray-500 dark:text-gray-400">
          Secure • Built for Professionals
        </footer>
      </div>
    </main>
  );
}