import { LightningElement, track } from 'lwc';
import getExecutiveSummary from '@salesforce/apex/DashboardService.getExecutiveSummary';
import getRevenueTrend     from '@salesforce/apex/DashboardService.getRevenueTrend';
import getLeadFunnel       from '@salesforce/apex/DashboardService.getLeadFunnel';
import getAIInsightsFeed   from '@salesforce/apex/DashboardService.getAIInsightsFeed';

export default class OneopsDashboard extends LightningElement {

    @track kpis           = {};
    @track funnelData     = [];
    @track aiInsights     = [];
    @track isLoading      = true;
    @track lastRefreshLabel = 'now';
    @track revMonths      = 6;

    connectedCallback() {
        this.loadAll();
    }

    async loadAll() {
        this.isLoading = true;
        await Promise.all([
            this.loadKPIs(),
            this.loadFunnel(),
            this.loadInsights()
        ]);
        this.isLoading = false;
        this.lastRefreshLabel = new Date().toLocaleTimeString([], { hour: '2-digit', minute: '2-digit' });
    }

    async loadKPIs() {
        try {
            const result = await getExecutiveSummary();
            if (result && result.success) {
                const d = result.data;
                this.kpis = {
                    newLeads:       d.crm?.newLeads || 0,
                    hotLeads:       d.crm?.hotLeads || 0,
                    pipelineValue:  d.sales?.pipelineValue || 0,
                    collected:      d.finance?.collected || 0,
                    outstanding:    d.finance?.outstanding || 0,
                    openTickets:    d.support?.openTickets || 0,
                    slaBreached:    d.support?.slaBreached || 0,
                    slaCompliance:  d.support?.slaCompliance || 100,
                    lowStockItems:  d.inventory?.lowStockItems || 0,
                    activeEmployees: d.hr?.activeEmployees || 0,
                    pendingLeave:   d.hr?.pendingLeave || 0
                };
            }
        } catch (_) {}
    }

    async loadFunnel() {
        try {
            const result = await getLeadFunnel();
            if (result && result.success) {
                const data = result.data || [];
                const max = data.reduce((m, s) => Math.max(m, s.cnt || 0), 1);
                this.funnelData = data.map(s => ({
                    ...s,
                    barStyle: `width:${Math.round(((s.cnt || 0) / max) * 100)}%;background:var(--color-accent)`
                }));
            }
        } catch (_) {}
    }

    async loadInsights() {
        try {
            const result = await getAIInsightsFeed({ module: null });
            if (result && result.success) {
                this.aiInsights = (result.data || []).map(i => ({
                    ...i,
                    cardClass:     `insight-card insight-${(i.Severity__c || 'low').toLowerCase()}`,
                    severityClass: `insight-severity sev-${(i.Severity__c || 'low').toLowerCase()}`
                }));
            }
        } catch (_) {}
    }

    refresh() { this.loadAll(); }

    setRevMonths(event) {
        this.revMonths = parseInt(event.currentTarget.dataset.months, 10);
        this.loadRevenueTrend();
    }

    async loadRevenueTrend() {
        try {
            const result = await getRevenueTrend({ months: this.revMonths });
            if (result && result.success) {
                this.drawRevenueChart(result.data || []);
            }
        } catch (_) {}
    }

    renderedCallback() {
        if (!this._chartDrawn) {
            this._chartDrawn = true;
            this.loadRevenueTrend();
        }
    }

    drawRevenueChart(monthlyData) {
        const canvas = this.template.querySelector('.revenue-chart');
        if (!canvas) return;
        const ctx = canvas.getContext('2d');
        const W = canvas.offsetWidth || 400;
        const H = 200;
        canvas.width  = W;
        canvas.height = H;

        const values = monthlyData.map(m => m.total || 0);
        if (!values.length) return;

        const max  = Math.max(...values, 1);
        const padX = 40, padY = 20;
        const plotW = W - padX * 2;
        const plotH = H - padY * 2;
        const step  = plotW / Math.max(values.length - 1, 1);

        ctx.clearRect(0, 0, W, H);

        // Gradient fill
        const grad = ctx.createLinearGradient(0, padY, 0, padY + plotH);
        grad.addColorStop(0, 'rgba(200,155,60,0.25)');
        grad.addColorStop(1, 'rgba(200,155,60,0)');

        // Line path
        ctx.beginPath();
        values.forEach((v, i) => {
            const x = padX + i * step;
            const y = padY + plotH - (v / max) * plotH;
            i === 0 ? ctx.moveTo(x, y) : ctx.lineTo(x, y);
        });

        // Fill below line
        ctx.lineTo(padX + (values.length - 1) * step, padY + plotH);
        ctx.lineTo(padX, padY + plotH);
        ctx.closePath();
        ctx.fillStyle = grad;
        ctx.fill();

        // Stroke line
        ctx.beginPath();
        values.forEach((v, i) => {
            const x = padX + i * step;
            const y = padY + plotH - (v / max) * plotH;
            i === 0 ? ctx.moveTo(x, y) : ctx.lineTo(x, y);
        });
        ctx.strokeStyle = '#C89B3C';
        ctx.lineWidth   = 2;
        ctx.stroke();

        // Data points
        values.forEach((v, i) => {
            const x = padX + i * step;
            const y = padY + plotH - (v / max) * plotH;
            ctx.beginPath();
            ctx.arc(x, y, 4, 0, Math.PI * 2);
            ctx.fillStyle = '#C89B3C';
            ctx.fill();
            ctx.strokeStyle = '#0F1E35';
            ctx.lineWidth   = 2;
            ctx.stroke();
        });
    }

    get revBtn3()  { return `rev-btn ${this.revMonths === 3  ? 'rev-btn--active' : ''}`; }
    get revBtn6()  { return `rev-btn ${this.revMonths === 6  ? 'rev-btn--active' : ''}`; }
    get revBtn12() { return `rev-btn ${this.revMonths === 12 ? 'rev-btn--active' : ''}`; }

    viewInsights() {
        this.dispatchEvent(new CustomEvent('modulechange', { detail: { module: 'ai' }, bubbles: true, composed: true }));
    }
}
