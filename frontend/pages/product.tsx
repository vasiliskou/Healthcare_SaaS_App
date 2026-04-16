"use client"

import { useState, FormEvent } from 'react';
import { useAuth } from '@clerk/nextjs';
import DatePicker from 'react-datepicker';
import ReactMarkdown from 'react-markdown';
import remarkGfm from 'remark-gfm';
import remarkBreaks from 'remark-breaks';
import { fetchEventSource } from '@microsoft/fetch-event-source';
import { Protect, PricingTable, UserButton } from '@clerk/nextjs';

function ConsultationForm() {
    const { getToken } = useAuth();

    // Form state
    const [patientName, setPatientName] = useState('');
    const [visitDate, setVisitDate] = useState<Date | null>(new Date());
    const [notes, setNotes] = useState('');

    // Streaming state
    const [output, setOutput] = useState('');
    const [loading, setLoading] = useState(false);

    async function handleSubmit(e: FormEvent) {
        e.preventDefault();
        setOutput('');
        setLoading(true);

        const jwt = await getToken();
        if (!jwt) {
            setOutput('Authentication required');
            setLoading(false);
            return;
        }

        // Normalize API URL
        // - Remove anything after whitespace or '#' (common when pasting comments)
        // - Remove trailing slash
        const rawApiUrl = process.env.NEXT_PUBLIC_API_URL ?? '';
        const apiUrl = rawApiUrl
            .trim()
            .split(/[\s#]/, 1)[0]
            ?.replace(/\/$/, '') || '';
        if (!apiUrl) {
            setOutput('Error: API URL not configured. Please set NEXT_PUBLIC_API_URL.');
            setLoading(false);
            console.error('NEXT_PUBLIC_API_URL is not set');
            return;
        }

        let apiEndpoint: string;
        try {
            apiEndpoint = new URL('/api/consultation', apiUrl).toString();
        } catch {
            setOutput('Error: NEXT_PUBLIC_API_URL is not a valid URL. Example: http://127.0.0.1:8000');
            setLoading(false);
            console.error('Invalid NEXT_PUBLIC_API_URL:', rawApiUrl);
            return;
        }

        const controller = new AbortController();
        let buffer = '';

        try {
            await fetchEventSource(apiEndpoint, {            
                signal: controller.signal,
                method: 'POST',
                headers: {
                    'Content-Type': 'application/json',
                    Authorization: `Bearer ${jwt}`,
                },
                body: JSON.stringify({
                    patient_name: patientName,
                    date_of_visit: visitDate?.toISOString().slice(0, 10),
                    notes,
                }),
                async onopen(response) {
                    // If backend returns JSON error (e.g. 401/403/429), show it instead of failing on SSE parsing.
                    const contentType = response.headers.get('content-type') || '';
                    if (!response.ok) {
                        let detail = `Request failed (${response.status})`;
                        try {
                            if (contentType.includes('application/json')) {
                                const data = await response.json().catch(() => null);
                                if (data?.detail) detail = typeof data.detail === 'string' ? data.detail : JSON.stringify(data.detail);
                                else if (data) detail = JSON.stringify(data);
                            } else {
                                const text = await response.text().catch(() => '');
                                if (text) detail = text;
                            }
                        } catch {}
                        setOutput(`Error: ${detail}`);
                        setLoading(false);
                        controller.abort();
                        throw new Error(detail);
                    }

                    if (!contentType.includes('text/event-stream')) {
                        const text = await response.text().catch(() => '');
                        setOutput(`Error: Expected SSE stream, got "${contentType || 'unknown'}". ${text ? `Response: ${text}` : ''}`);
                        setLoading(false);
                        controller.abort();
                        throw new Error(`Expected text/event-stream, got ${contentType}`);
                    }
                },
                onmessage(ev) {
                    buffer += ev.data;
                    setOutput(buffer);
                },
                onclose() { 
                    setLoading(false); 
                },
                onerror(err) {
                    console.error('SSE error:', err);
                    console.error('API URL used:', apiEndpoint);
                    console.error('Response might be HTML instead of SSE stream - check if endpoint exists');
                    if (err instanceof Error && err.message) {
                        // If onopen threw a meaningful message, surface it.
                        setOutput((prev) => prev || `Error: ${err.message}`);
                    } else {
                        setOutput(`Error: Failed to connect to backend. Check browser console for details.`);
                    }
                    controller.abort();
                    setLoading(false);
                },
            });
        } catch (err) {
            console.error('Request failed:', err);
            setOutput(`Error: ${err instanceof Error ? err.message : 'Unknown error'}`);
            setLoading(false);
        }
    }

    return (
        <div className="container mx-auto px-4 py-12 max-w-3xl">
            <h1 className="text-4xl font-bold text-gray-900 dark:text-gray-100 mb-8">
                Consultation Notes
            </h1>

            <form onSubmit={handleSubmit} className="space-y-6 bg-white dark:bg-gray-800 rounded-xl shadow-lg p-8">
                <div className="space-y-2">
                    <label htmlFor="patient" className="block text-sm font-medium text-gray-700 dark:text-gray-300">
                        Patient Name
                    </label>
                    <input
                        id="patient"
                        type="text"
                        required
                        value={patientName}
                        onChange={(e) => setPatientName(e.target.value)}
                        className="w-full px-4 py-2 border border-gray-300 dark:border-gray-600 rounded-lg focus:ring-2 focus:ring-blue-500 focus:border-transparent dark:bg-gray-700 dark:text-white"
                        placeholder="Enter patient's full name"
                    />
                </div>

                <div className="space-y-2">
                    <label htmlFor="date" className="block text-sm font-medium text-gray-700 dark:text-gray-300">
                        Date of Visit
                    </label>
                    <DatePicker
                        id="date"
                        selected={visitDate}
                        onChange={(d: Date | null) => setVisitDate(d)}
                        dateFormat="yyyy-MM-dd"
                        placeholderText="Select date"
                        required
                        className="w-full px-4 py-2 border border-gray-300 dark:border-gray-600 rounded-lg focus:ring-2 focus:ring-blue-500 focus:border-transparent dark:bg-gray-700 dark:text-white"
                    />
                </div>

                <div className="space-y-2">
                    <label htmlFor="notes" className="block text-sm font-medium text-gray-700 dark:text-gray-300">
                        Consultation Notes
                    </label>
                    <textarea
                        id="notes"
                        required
                        rows={8}
                        value={notes}
                        onChange={(e) => setNotes(e.target.value)}
                        className="w-full px-4 py-2 border border-gray-300 dark:border-gray-600 rounded-lg focus:ring-2 focus:ring-blue-500 focus:border-transparent dark:bg-gray-700 dark:text-white"
                        placeholder="Enter detailed consultation notes..."
                    />
                </div>

                <button 
                    type="submit" 
                    disabled={loading}
                    className="w-full bg-blue-600 hover:bg-blue-700 disabled:bg-blue-400 text-white font-semibold py-3 px-6 rounded-lg transition-colors duration-200"
                >
                    {loading ? 'Generating Summary...' : 'Generate Summary'}
                </button>
            </form>

            {output && (
                <section className="mt-8 bg-gray-50 dark:bg-gray-800 rounded-xl shadow-lg p-8">
                    <div className="markdown-content prose prose-blue dark:prose-invert max-w-none">
                        <ReactMarkdown remarkPlugins={[remarkGfm, remarkBreaks]}>
                            {output}
                        </ReactMarkdown>
                    </div>
                </section>
            )}
        </div>
    );
}

export default function Product() {
    return (
        <main className="min-h-screen bg-gradient-to-br from-gray-50 to-gray-100 dark:from-gray-900 dark:to-gray-800">
            {/* User Menu in Top Right */}
            <div className="absolute top-4 right-4">
                <UserButton showName={true} />
            </div>

            {/* Subscription Protection */}
            <Protect
                plan="premium_subscription"
                fallback={
                    <div className="container mx-auto px-4 py-12">
                        <header className="text-center mb-12">
                            <h1 className="text-5xl font-bold bg-gradient-to-r from-blue-600 to-indigo-600 bg-clip-text text-transparent mb-4">
                                Healthcare Professional Plan
                            </h1>
                            <p className="text-gray-600 dark:text-gray-400 text-lg mb-8">
                                Streamline your patient consultations with AI-powered summaries
                            </p>
                        </header>
                        <div className="max-w-4xl mx-auto">
                            <PricingTable />
                        </div>
                    </div>
                }
            >
                <ConsultationForm />
            </Protect>
        </main>
    );
}