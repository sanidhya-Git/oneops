import { createElement } from 'lwc';
import OneopsKpiCard from 'c/oneopsKpiCard';

function createComponent(props = {}) {
    const el = createElement('c-oneops-kpi-card', { is: OneopsKpiCard });
    Object.assign(el, props);
    document.body.appendChild(el);
    return el;
}

afterEach(() => {
    while (document.body.firstChild) document.body.removeChild(document.body.firstChild);
});

describe('oneopsKpiCard — formattedValue (via DOM)', () => {
    it('shows dash when value is null', async () => {
        const el = createComponent({ value: null });
        await Promise.resolve();
        expect(el.shadowRoot.querySelector('.kpi-value').textContent).toBe('—');
    });

    it('shows dash when value is undefined', async () => {
        const el = createComponent({ value: undefined });
        await Promise.resolve();
        expect(el.shadowRoot.querySelector('.kpi-value').textContent).toBe('—');
    });

    it('shows plain number for values below 1000', async () => {
        const el = createComponent({ value: 42 });
        await Promise.resolve();
        expect(el.shadowRoot.querySelector('.kpi-value').textContent).toBe('42');
    });

    it('abbreviates values ≥1000 as K', async () => {
        const el = createComponent({ value: 2500 });
        await Promise.resolve();
        expect(el.shadowRoot.querySelector('.kpi-value').textContent).toContain('2.5K');
    });

    it('abbreviates values ≥1000000 as M', async () => {
        const el = createComponent({ value: 3200000 });
        await Promise.resolve();
        expect(el.shadowRoot.querySelector('.kpi-value').textContent).toContain('3.2M');
    });

    it('prepends prefix to value', async () => {
        const el = createComponent({ value: 99, prefix: '$' });
        await Promise.resolve();
        expect(el.shadowRoot.querySelector('.kpi-value').textContent).toContain('$99');
    });

    it('appends suffix to value', async () => {
        const el = createComponent({ value: 75, suffix: '%' });
        await Promise.resolve();
        expect(el.shadowRoot.querySelector('.kpi-value').textContent).toContain('75%');
    });

    it('converts string value to number and formats', async () => {
        const el = createComponent({ value: '1500' });
        await Promise.resolve();
        expect(el.shadowRoot.querySelector('.kpi-value').textContent).toContain('1.5K');
    });

    it('renders label text', async () => {
        const el = createComponent({ label: 'Revenue', value: 0 });
        await Promise.resolve();
        expect(el.shadowRoot.querySelector('.kpi-label').textContent).toBe('Revenue');
    });
});

describe('oneopsKpiCard — trend (via DOM)', () => {
    it('does not render trend span when trend is null', async () => {
        const el = createComponent({ trend: null });
        await Promise.resolve();
        expect(el.shadowRoot.querySelector('.kpi-trend')).toBeNull();
    });

    it('does not render trend span when trend is undefined', async () => {
        const el = createComponent({ trend: undefined });
        await Promise.resolve();
        expect(el.shadowRoot.querySelector('.kpi-trend')).toBeNull();
    });

    it('renders trend-up class for positive trend', async () => {
        const el = createComponent({ trend: 10 });
        await Promise.resolve();
        expect(el.shadowRoot.querySelector('.trend-up')).not.toBeNull();
    });

    it('renders trend-down class for negative trend', async () => {
        const el = createComponent({ trend: -5 });
        await Promise.resolve();
        expect(el.shadowRoot.querySelector('.trend-down')).not.toBeNull();
    });

    it('renders trend-up for zero trend', async () => {
        const el = createComponent({ trend: 0 });
        await Promise.resolve();
        expect(el.shadowRoot.querySelector('.trend-up')).not.toBeNull();
    });

    it('shows trend value text', async () => {
        const el = createComponent({ trend: 12 });
        await Promise.resolve();
        const span = el.shadowRoot.querySelector('.kpi-trend');
        expect(span.textContent).toContain('12');
    });
});

describe('oneopsKpiCard — card variant class (via DOM)', () => {
    it('applies kpi-card--default class for default variant', async () => {
        const el = createComponent({ variant: 'default', value: 0 });
        await Promise.resolve();
        const card = el.shadowRoot.querySelector('[role="region"]');
        expect(card.className).toContain('kpi-card--default');
    });

    it('applies kpi-card--danger class for danger variant', async () => {
        const el = createComponent({ variant: 'danger', value: 0 });
        await Promise.resolve();
        const card = el.shadowRoot.querySelector('[role="region"]');
        expect(card.className).toContain('kpi-card--danger');
    });

    it('applies kpi-card--ai class for ai variant', async () => {
        const el = createComponent({ variant: 'ai', value: 0 });
        await Promise.resolve();
        const card = el.shadowRoot.querySelector('[role="region"]');
        expect(card.className).toContain('kpi-card--ai');
    });

    it('applies kpi-card--success class for success variant', async () => {
        const el = createComponent({ variant: 'success', value: 0 });
        await Promise.resolve();
        const card = el.shadowRoot.querySelector('[role="region"]');
        expect(card.className).toContain('kpi-card--success');
    });
});

describe('oneopsKpiCard — loading state (via DOM)', () => {
    it('renders loading overlay when isLoading is true', async () => {
        const el = createComponent({ isLoading: true, value: 0 });
        await Promise.resolve();
        expect(el.shadowRoot.querySelector('.kpi-loading')).not.toBeNull();
    });

    it('does not render loading overlay when isLoading is false', async () => {
        const el = createComponent({ isLoading: false, value: 0 });
        await Promise.resolve();
        expect(el.shadowRoot.querySelector('.kpi-loading')).toBeNull();
    });
});

describe('oneopsKpiCard — @api aria-label', () => {
    it('sets aria-label from label prop', async () => {
        const el = createComponent({ label: 'Total Leads', value: 0 });
        await Promise.resolve();
        const card = el.shadowRoot.querySelector('[role="region"]');
        expect(card.getAttribute('aria-label')).toBe('Total Leads');
    });
});
