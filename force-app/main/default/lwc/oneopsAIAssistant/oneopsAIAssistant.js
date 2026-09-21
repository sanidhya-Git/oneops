import { LightningElement, track } from 'lwc';
import chatQuery from '@salesforce/apex/AIEngineService.chatQuery';

const SUGGESTIONS = [
    'Show me hot leads from this week',
    'Which tickets are breaching SLA?',
    'Summarize my pipeline forecast',
    'Which inventory items need reordering?',
];

export default class OneopsAIAssistant extends LightningElement {

    @track isOpen    = false;
    @track messages  = [];
    @track inputText = '';
    @track isTyping  = false;
    @track isSending = false;
    @track providerLabel = 'OpenAI GPT-4o';

    suggestions = SUGGESTIONS;

    get showWelcome() {
        return this.messages.length === 0 && !this.isTyping;
    }

    openChat()  { this.isOpen = true; }
    closeChat() { this.isOpen = false; }
    clearChat() { this.messages = []; }

    handleInput(event) {
        this.inputText = event.target.value;
    }

    handleKeydown(event) {
        if (event.key === 'Enter' && !event.shiftKey) {
            event.preventDefault();
            this.sendMessage();
        }
    }

    handleSuggestion(event) {
        this.inputText = event.currentTarget.dataset.text;
        this.sendMessage();
    }

    async sendMessage() {
        const text = this.inputText.trim();
        if (!text || this.isSending) return;

        this.addMessage(text, 'user');
        this.inputText = '';
        this.isTyping  = true;
        this.isSending = true;

        try {
            const context = this.buildContext();
            const result  = await chatQuery({ userMessage: text, conversationContext: context });

            this.isTyping = false;
            if (result && result.success) {
                const data = result.data;
                const reply = data && data.reply ? data.reply : JSON.stringify(data);
                if (result.meta && result.meta.aiProvider) {
                    this.providerLabel = result.meta.aiProvider;
                }
                this.addMessage(reply, 'ai');
            } else {
                this.addMessage('I encountered an issue processing your request. Please try again.', 'ai');
            }
        } catch (error) {
            this.isTyping = false;
            this.addMessage('Connection error. Please check your network and try again.', 'ai');
        } finally {
            this.isSending = false;
            this.scrollToBottom();
        }
    }

    addMessage(text, role) {
        const id = Date.now() + Math.random();
        const now = new Date();
        this.messages = [...this.messages, {
            id,
            text,
            role,
            isAI:     role === 'ai',
            cssClass: `msg ${role === 'ai' ? 'ai-message' : 'user-message'}`,
            time:     now.toLocaleTimeString([], { hour: '2-digit', minute: '2-digit' })
        }];
    }

    buildContext() {
        const last5 = this.messages.slice(-5);
        return JSON.stringify(last5.map(m => ({ role: m.role, content: m.text })));
    }

    scrollToBottom() {
        const el = this.template.querySelector('.ai-messages');
        if (el) setTimeout(() => { el.scrollTop = el.scrollHeight; }, 50);
    }
}
