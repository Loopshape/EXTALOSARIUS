// services/orchestratorService.ts

type OrchestratorMessage = {
    type: 'orchestratorProgress' | 'orchestratorError' | 'orchestratorComplete' | 'error';
    output?: string;
    error?: string;
    message?: string;
    code?: number;
};

type MessageHandler = (message: OrchestratorMessage) => void;

class OrchestratorService {
    private ws: WebSocket | null = null;
    private handlers: MessageHandler[] = [];
    private isConnected: boolean = false;
    private reconnectionAttempts: number = 0;
    private maxReconnectionAttempts: number = 5;
    private reconnectionDelay: number = 2000; // 2 seconds

    constructor() {
        this.connect();
    }

    private connect() {
        if (this.ws && (this.ws.readyState === WebSocket.OPEN || this.ws.readyState === WebSocket.CONNECTING)) {
            return; // Already connected or connecting
        }

        if (this.reconnectionAttempts >= this.maxReconnectionAttempts) {
            console.error('Max reconnection attempts reached. Could not connect to WebSocket.');
            return;
        }

        console.log(`Attempting to connect to WebSocket (attempt ${this.reconnectionAttempts + 1}/${this.maxReconnectionAttempts})...`);
        this.ws = new WebSocket('ws://localhost:3000');

        this.ws.onopen = () => {
            console.log('WebSocket connected.');
            this.isConnected = true;
            this.reconnectionAttempts = 0; // Reset attempts on successful connection
        };

        this.ws.onmessage = (event) => {
            try {
                const message: OrchestratorMessage = JSON.parse(event.data as string);
                this.handlers.forEach(handler => handler(message));
            } catch (e) {
                console.error('Failed to parse WebSocket message:', e, event.data);
            }
        };

        this.ws.onclose = (event) => {
            console.warn('WebSocket disconnected:', event.code, event.reason);
            this.isConnected = false;
            // Attempt to reconnect if not explicitly closed and max attempts not reached
            if (!event.wasClean && this.reconnectionAttempts < this.maxReconnectionAttempts) {
                this.reconnectionAttempts++;
                setTimeout(() => this.connect(), this.reconnectionDelay);
            }
        };

        this.ws.onerror = (error) => {
            console.error('WebSocket error:', error);
            this.ws?.close(); // Force close on error to trigger onclose and reconnection logic
        };
    }

    public sendMessage(type: string, payload: any = {}) {
        if (this.ws && this.ws.readyState === WebSocket.OPEN) {
            this.ws.send(JSON.stringify({ type, ...payload }));
        } else {
            console.error('WebSocket not connected. Message not sent:', { type, ...payload });
            // Optionally, queue messages or attempt to reconnect
            if (!this.isConnected) {
                this.connect(); // Try to reconnect if not connected
            }
        }
    }

    public onMessage(handler: MessageHandler) {
        this.handlers.push(handler);
        return () => { // Return a cleanup function
            this.handlers = this.handlers.filter(h => h !== handler);
        };
    }

    public sendPrompt(prompt: string) {
        this.sendMessage('prompt', { prompt });
    }

    public close() {
        if (this.ws) {
            this.ws.close(1000, 'Client initiated close');
            this.ws = null;
            this.isConnected = false;
        }
    }
}

export const orchestratorService = new OrchestratorService();
