import React, { useState, useEffect, useRef } from 'react';
import Header from './components/Header';
import Loader from './components/Loader';
import FeedbackDisplay from './components/FeedbackDisplay';
import { SUPPORTED_LANGUAGES } from './constants';
import { reviewCodeWithGemini } from './services/geminiService';

declare global {
  interface Window {
    hljs: any;
  }
}

import { orchestratorService } from './services/orchestratorService';

const App: React.FC = () => {
  const [code, setCode] = useState<string>('');
  const [language, setLanguage] = useState<string>('javascript');
  const [feedback, setFeedback] = useState<string>('');
  const [isLoading, setIsLoading] = useState<boolean>(false);
  const [error, setError] = useState<string | null>(null);

  const [orchestrationPrompt, setOrchestrationPrompt] = useState<string>('');
  const [orchestrationOutput, setOrchestrationOutput] = useState<string[]>([]);
  const [isOrchestrating, setIsOrchestrating] = useState<boolean>(false);

  // Removed old Ollama state
  // const [ollamaEndpoint, setOllamaEndpoint] = useState<string>('http://localhost:11434/api/generate');
  // const [isSendingToOllama, setIsSendingToOllama] = useState<boolean>(false);
  // const [ollamaStatus, setOllamaStatus] = useState<string | null>(null);

  const [highlightedCode, setHighlightedCode] = useState('');
  const [copyButtonText, setCopyButtonText] = useState('Copy Code');
  const preRef = useRef<HTMLPreElement>(null);
  const textAreaRef = useRef<HTMLTextAreaElement>(null);
  const detectionTimeoutRef = useRef<number | null>(null);
  const cursorRef = useRef<number | null>(null);
  const languageUpdateFromAutoDetect = useRef(false);


  // Load state from localStorage on initial mount
  useEffect(() => {
    try {
      const savedCode = localStorage.getItem('gemini-code-reviewer-code');
      const savedLanguage = localStorage.getItem('gemini-code-reviewer-language');
      if (savedCode) {
        setCode(savedCode);
      }
      if (savedLanguage && SUPPORTED_LANGUAGES.some(lang => lang.value === savedLanguage)) {
        setLanguage(savedLanguage);
      }
    } catch (e) {
      console.error('Could not load from localStorage', e);
    }
  }, []);

  // Save code to localStorage on change
  useEffect(() => {
    try {
      // Don't save the initial empty state on first load if there's nothing there
      if (code || localStorage.getItem('gemini-code-reviewer-code')) {
        localStorage.setItem('gemini-code-reviewer-code', code);
      }
    } catch (e) {
      console.error('Could not save code to localStorage', e);
    }
  }, [code]);

  // Save language to localStorage on change
  useEffect(() => {
    try {
      localStorage.setItem('gemini-code-reviewer-language', language);
    } catch (e) {
      console.error('Could not save language to localStorage', e);
    }
  }, [language]);


  useEffect(() => {
    // Initial check for API key on mount
    if (!process.env.API_KEY) {
        setError("CRITICAL ERROR: API_KEY environment variable not found. The application cannot function without it.");
    }
  }, []);

  // Effect for OrchestratorService WebSocket listener
  useEffect(() => {
    const cleanup = orchestratorService.onMessage(message => {
      switch (message.type) {
        case 'orchestratorProgress':
          setOrchestrationOutput(prev => [...prev, message.output || '']);
          break;
        case 'orchestratorError':
          setOrchestrationOutput(prev => [...prev, `Error: ${message.error || message.message}`]);
          setIsOrchestrating(false);
          setError(message.error || message.message || 'An unknown orchestration error occurred.');
          break;
        case 'orchestratorComplete':
          setOrchestrationOutput(prev => [...prev, `Orchestration complete with code: ${message.code}`]);
          setIsOrchestrating(false);
          break;
        case 'error': // Generic error from WebSocket
          setOrchestrationOutput(prev => [...prev, `WebSocket Error: ${message.message}`]);
          setIsOrchestrating(false);
          setError(message.message || 'A generic WebSocket error occurred.');
          break;
      }
    });

    return () => {
      cleanup();
    };
  }, []);

  // Effect to set cursor position after state updates from keydown handlers
  useEffect(() => {
    if (textAreaRef.current && cursorRef.current !== null) {
      textAreaRef.current.selectionStart = cursorRef.current;
      textAreaRef.current.selectionEnd = cursorRef.current;
      cursorRef.current = null; // Reset after use
    }
  }, [highlightedCode]); // Depend on highlightedCode as it re-renders after code state changes

  const normalizeLanguage = (lang: string): string => {
    const langMap: { [key: string]: string } = {
        js: 'javascript',
        jsx: 'javascript',
        ts: 'typescript',
        tsx: 'typescript',
        py: 'python',
        golang: 'go',
        rs: 'rust',
        xml: 'html', // hljs detects html as xml
        cs: 'csharp',
        'c++': 'cpp',
        rb: 'ruby',
        kt: 'kotlin',
    };
    return langMap[lang] || lang;
  };

  // Effect 1: Auto-detect language and highlight on code change (debounced)
  useEffect(() => {
    if (detectionTimeoutRef.current) clearTimeout(detectionTimeoutRef.current);

    detectionTimeoutRef.current = window.setTimeout(() => {
        if (code.trim()) {
            const result = window.hljs.highlightAuto(code);
            const detectedLang = normalizeLanguage(result.language || 'plaintext');
            if (SUPPORTED_LANGUAGES.some(l => l.value === detectedLang) && detectedLang !== language) {
                languageUpdateFromAutoDetect.current = true;
                setLanguage(detectedLang);
            }
            setHighlightedCode(window.hljs.highlight(code, { language: detectedLang, ignoreIllegals: true }).value);
        } else {
            setHighlightedCode('');
        }
    }, 200);

    return () => {
        if (detectionTimeoutRef.current) {
            clearTimeout(detectionTimeoutRef.current);
        }
    };
  }, [code]);

  // Re-run highlighting if language is manually changed
  useEffect(() => {
      if (languageUpdateFromAutoDetect.current) {
          languageUpdateFromAutoDetect.current = false;
          return;
      }
      if (code.trim()) {
          setHighlightedCode(window.hljs.highlight(code, { language, ignoreIllegals: true }).value);
      } else {
          setHighlightedCode('');
      }
  }, [language]);


  const handleCodeChange = (e: React.ChangeEvent<HTMLTextAreaElement>) => {
    setCode(e.target.value);
  };

  const handleLanguageChange = (e: React.ChangeEvent<HTMLSelectElement>) => {
    setLanguage(e.target.value);
  };

  const handleReview = async () => {
    if (isLoading) return;
    setIsLoading(true);
    setError(null);
    setFeedback('');
    try {
      const result = await reviewCodeWithGemini(code, language);
      setFeedback(result);
    } catch (err) {
      setError(err instanceof Error ? err.message : 'An unknown error occurred.');
    } finally {
      setIsLoading(false);
    }
  };

  const handleRunOrchestration = () => {
    if (isOrchestrating) return;
    if (!orchestrationPrompt.trim()) {
      alert('Please enter a prompt for orchestration.');
      return;
    }
    setOrchestrationOutput([]); // Clear previous output
    setIsOrchestrating(true);
    setError(null);
    orchestratorService.sendPrompt(orchestrationPrompt);
  };


  
  const handleKeyDown = (e: React.KeyboardEvent<HTMLTextAreaElement>) => {
    const { value, selectionStart, selectionEnd } = e.currentTarget;
    if (e.key === 'Tab') {
      e.preventDefault();
      const tab = '  '; // 2 spaces for a tab
      const newValue = value.substring(0, selectionStart) + tab + value.substring(selectionEnd);
      setCode(newValue);
      cursorRef.current = selectionStart + tab.length;
    }
  };

  const handleCopyCode = () => {
    if (!code) return;
    navigator.clipboard.writeText(code).then(() => {
      setCopyButtonText('Copied!');
      setTimeout(() => setCopyButtonText('Copy Code'), 2000);
    }).catch(err => {
      console.error('Failed to copy code: ', err);
      setCopyButtonText('Copy Failed');
      setTimeout(() => setCopyButtonText('Copy Code'), 2000);
    });
  };

  return (
    <div className="min-h-screen bg-gray-900 text-gray-100 flex flex-col font-sans">
      <Header />
      <main className="flex-1 flex flex-col p-4 pt-24 container mx-auto">
        <div className="flex-1 grid grid-cols-1 md:grid-cols-2 gap-4 min-h-[60vh]">
            {/* Code Editor Panel */}
            <div className="flex flex-col h-full">
                <div className="flex justify-between items-center p-2 bg-gray-800 border-b border-gray-700 rounded-t-lg">
                    <span className="font-mono text-sm text-gray-400">Your Code</span>
                    <div className="flex items-center gap-4">
                        <button
                            onClick={handleCopyCode}
                            disabled={!code.trim()}
                            className={`bg-gray-700 hover:bg-gray-600 disabled:bg-gray-800 disabled:text-gray-500 disabled:cursor-not-allowed text-gray-300 text-xs font-mono py-1 px-3 rounded transition-all duration-200 ${copyButtonText === 'Copied!' ? '!bg-green-600 text-white' : ''}`}
                            aria-label="Copy code to clipboard"
                        >
                            {copyButtonText}
                        </button>
                        <select
                            value={language}
                            onChange={handleLanguageChange}
                            className="bg-gray-700 border border-gray-600 rounded px-2 py-1 text-sm text-white focus:outline-none focus:ring-2 focus:ring-cyan-500"
                            aria-label="Select programming language"
                        >
                            {SUPPORTED_LANGUAGES.map((lang) => (
                                <option key={lang.value} value={lang.value}>
                                    {lang.label}
                                </option>
                            ))}
                        </select>
                    </div>
                </div>
                <div className="relative flex-1 bg-gray-900 ring-1 ring-gray-700 rounded-b-lg">
                    <textarea
                        ref={textAreaRef}
                        value={code}
                        onChange={handleCodeChange}
                        onKeyDown={handleKeyDown}
                        className="absolute inset-0 w-full h-full p-4 font-mono text-base bg-transparent text-transparent caret-white resize-none z-10 focus:outline-none"
                        spellCheck="false"
                        aria-label="Code Input"
                    />
                    <pre
                        ref={preRef}
                        className="absolute inset-0 w-full h-full p-4 font-mono text-base pointer-events-none overflow-auto"
                        aria-hidden="true"
                    >
                        <code dangerouslySetInnerHTML={{ __html: highlightedCode }} />
                    </pre>
                </div>
            </div>

            {/* Feedback Panel */}
            <div className="flex flex-col h-full">
                <div className="flex justify-between items-center p-2 bg-gray-800 border-b border-gray-700 rounded-t-lg">
                    <span className="font-mono text-sm text-gray-400">Gemini's Feedback</span>
                </div>
                <div className="relative flex-1 bg-gray-900 ring-1 ring-gray-700 rounded-b-lg">
                    {isLoading && <Loader />}
                    <FeedbackDisplay feedback={feedback} error={error} />
                </div>
            </div>
        </div>

        {/* Action Bar */}
        <div className="py-4 flex flex-col sm:flex-row items-center justify-center gap-4">
            <button
                onClick={handleReview}
                disabled={isLoading || !code.trim()}
                className="w-full sm:w-auto bg-cyan-600 hover:bg-cyan-500 disabled:bg-gray-600 disabled:cursor-not-allowed text-white font-bold py-3 px-8 rounded-lg shadow-lg transform hover:scale-105 transition-all duration-300 ease-in-out"
            >
                {isLoading ? 'Reviewing...' : 'Review Code'}
            </button>
        </div>

        {/* Orchestration Panel */}
        <div className="bg-gray-800/60 p-4 rounded-lg ring-1 ring-gray-700 mt-4">
            <h3 className="text-lg font-semibold mb-3 text-white">Multi-Agent Orchestration</h3>
            <div className="flex flex-col sm:flex-row items-center gap-4 mb-2">
                <textarea
                    value={orchestrationPrompt}
                    onChange={(e) => setOrchestrationPrompt(e.target.value)}
                    className="flex-grow bg-gray-700 border border-gray-600 rounded px-3 py-2 text-sm text-white focus:outline-none focus:ring-2 focus:ring-cyan-500 w-full sm:w-auto min-h-[60px]"
                    placeholder="Enter prompt for multi-agent orchestration (e.g., 'Create a Python script to fetch stock data')."
                    aria-label="Orchestration Prompt"
                />
                <button
                    onClick={handleRunOrchestration}
                    disabled={isOrchestrating || !orchestrationPrompt.trim()}
                    className="w-full sm:w-auto bg-purple-600 hover:bg-purple-500 disabled:bg-gray-600 disabled:cursor-not-allowed text-white font-bold py-2 px-6 rounded transition-colors duration-200"
                >
                    {isOrchestrating ? 'Orchestrating...' : 'Run Orchestration'}
                </button>
            </div>
            {orchestrationOutput.length > 0 && (
                <div className="mt-3 p-3 bg-gray-900 rounded max-h-60 overflow-y-auto">
                    <pre className="whitespace-pre-wrap font-mono text-xs text-gray-300">
                        {orchestrationOutput.map((line, index) => <span key={index}>{line}</span>)}
                    </pre>
                </div>
            )}
        </div>
      </main>
    </div>
  );
};

export default App;
