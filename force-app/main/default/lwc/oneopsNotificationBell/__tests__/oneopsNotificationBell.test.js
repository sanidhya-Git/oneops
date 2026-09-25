jest.mock('@salesforce/apex/NotificationService.getMyNotifications', () => jest.fn(), { virtual: true });
jest.mock('@salesforce/apex/NotificationService.markAsRead',         () => jest.fn(), { virtual: true });
jest.mock('@salesforce/apex/NotificationService.getUnreadCount',     () => jest.fn(), { virtual: true });

import { createElement } from 'lwc';
import OneopsNotificationBell from 'c/oneopsNotificationBell';
import getMyNotifications from '@salesforce/apex/NotificationService.getMyNotifications';
import markAsRead         from '@salesforce/apex/NotificationService.markAsRead';
import getUnreadCount     from '@salesforce/apex/NotificationService.getUnreadCount';

function flushPromises() {
    return new Promise(resolve => setTimeout(resolve, 0));
}

const SAMPLE_NOTIFICATIONS = [
    { Id: 'n1', Title__c: 'Lead assigned', Body__c: 'New lead', Is_Read__c: false, Module__c: 'CRM',     Sent_At__c: new Date(Date.now() - 60000).toISOString() },
    { Id: 'n2', Title__c: 'Ticket updated', Body__c: 'Updated', Is_Read__c: true,  Module__c: 'Support', Sent_At__c: new Date(Date.now() - 3600000).toISOString() },
    { Id: 'n3', Title__c: 'Invoice due',    Body__c: 'Pay now',  Is_Read__c: false, Module__c: 'Finance', Sent_At__c: new Date(Date.now() - 86400000).toISOString() },
];

function createComponent() {
    const el = createElement('c-oneops-notification-bell', { is: OneopsNotificationBell });
    document.body.appendChild(el);
    return el;
}

beforeEach(() => jest.useFakeTimers());
afterEach(() => {
    while (document.body.firstChild) document.body.removeChild(document.body.firstChild);
    jest.clearAllMocks();
    jest.useRealTimers();
});

describe('oneopsNotificationBell — initial state', () => {
    it('starts closed', () => {
        getUnreadCount.mockResolvedValue({ success: true, data: { unreadCount: 0 } });
        const el = createComponent();
        expect(el.isOpen).toBe(false);
    });

    it('starts with 0 unread count', () => {
        getUnreadCount.mockResolvedValue({ success: true, data: { unreadCount: 0 } });
        const el = createComponent();
        expect(el.unreadCount).toBe(0);
    });

    it('hasUnread is false when unreadCount is 0', () => {
        getUnreadCount.mockResolvedValue({ success: true, data: { unreadCount: 0 } });
        const el = createComponent();
        expect(el.hasUnread).toBe(false);
    });

    it('isEmpty is true before notifications are loaded', () => {
        getUnreadCount.mockResolvedValue({ success: true, data: { unreadCount: 0 } });
        const el = createComponent();
        expect(el.isEmpty).toBe(true);
    });
});

describe('oneopsNotificationBell — fetchUnreadCount', () => {
    it('fetches unread count on connect', async () => {
        getUnreadCount.mockResolvedValue({ success: true, data: { unreadCount: 5 } });
        const el = createComponent();
        await Promise.resolve();
        await Promise.resolve();
        jest.runAllTimers();
        await Promise.resolve();
        expect(getUnreadCount).toHaveBeenCalled();
    });

    it('sets unreadCount from apex result', async () => {
        getUnreadCount.mockResolvedValue({ success: true, data: { unreadCount: 7 } });
        const el = createComponent();
        await Promise.resolve();
        await Promise.resolve();
        expect(el.unreadCount).toBe(7);
    });

    it('hasUnread is true when unreadCount > 0', async () => {
        getUnreadCount.mockResolvedValue({ success: true, data: { unreadCount: 3 } });
        const el = createComponent();
        await Promise.resolve();
        await Promise.resolve();
        expect(el.hasUnread).toBe(true);
    });

    it('handles apex error gracefully', async () => {
        getUnreadCount.mockRejectedValue(new Error('Network error'));
        const el = createComponent();
        await Promise.resolve();
        await Promise.resolve();
        expect(el.unreadCount).toBe(0);
    });

    it('polls unread count every 30 seconds', async () => {
        getUnreadCount.mockResolvedValue({ success: true, data: { unreadCount: 1 } });
        const el = createComponent();
        await Promise.resolve();
        await Promise.resolve();
        const callCount = getUnreadCount.mock.calls.length;
        jest.advanceTimersByTime(30000);
        await Promise.resolve();
        await Promise.resolve();
        expect(getUnreadCount.mock.calls.length).toBeGreaterThan(callCount);
    });
});

describe('oneopsNotificationBell — togglePanel', () => {
    it('opens panel on first toggle', async () => {
        getUnreadCount.mockResolvedValue({ success: true, data: { unreadCount: 0 } });
        getMyNotifications.mockResolvedValue({ success: true, data: [] });
        const el = createComponent();
        await Promise.resolve();
        await el.togglePanel();
        expect(el.isOpen).toBe(true);
    });

    it('closes panel on second toggle', async () => {
        getUnreadCount.mockResolvedValue({ success: true, data: { unreadCount: 0 } });
        getMyNotifications.mockResolvedValue({ success: true, data: [] });
        const el = createComponent();
        await Promise.resolve();
        await el.togglePanel();
        await el.togglePanel();
        expect(el.isOpen).toBe(false);
    });

    it('fetches notifications when opening', async () => {
        getUnreadCount.mockResolvedValue({ success: true, data: { unreadCount: 0 } });
        getMyNotifications.mockResolvedValue({ success: true, data: SAMPLE_NOTIFICATIONS });
        const el = createComponent();
        await Promise.resolve();
        await el.togglePanel();
        await Promise.resolve();
        expect(getMyNotifications).toHaveBeenCalledWith({ limit_: 20 });
    });

    it('does not fetch notifications when closing', async () => {
        getUnreadCount.mockResolvedValue({ success: true, data: { unreadCount: 0 } });
        getMyNotifications.mockResolvedValue({ success: true, data: [] });
        const el = createComponent();
        await Promise.resolve();
        await el.togglePanel();   // open - fetches
        getMyNotifications.mockClear();
        await el.togglePanel();   // close - should not fetch
        expect(getMyNotifications).not.toHaveBeenCalled();
    });
});

describe('oneopsNotificationBell — notification rendering', () => {
    it('decorates notifications with cssClass for unread', async () => {
        getUnreadCount.mockResolvedValue({ success: true, data: { unreadCount: 2 } });
        getMyNotifications.mockResolvedValue({ success: true, data: SAMPLE_NOTIFICATIONS });
        const el = createComponent();
        await Promise.resolve();
        await el.togglePanel();
        await Promise.resolve();
        expect(el.notifications[0].cssClass).toContain('notif-unread');
        expect(el.notifications[1].cssClass).toContain('notif-read');
    });

    it('decorates notifications with correct dotStyle colors', async () => {
        getUnreadCount.mockResolvedValue({ success: true, data: { unreadCount: 0 } });
        getMyNotifications.mockResolvedValue({ success: true, data: SAMPLE_NOTIFICATIONS });
        const el = createComponent();
        await Promise.resolve();
        await el.togglePanel();
        await Promise.resolve();
        expect(el.notifications[0].dotStyle).toContain('#4D9DE0'); // CRM color
        expect(el.notifications[1].dotStyle).toContain('#FF453A'); // Support color
        expect(el.notifications[2].dotStyle).toContain('#FF3B30'); // Finance color
    });

    it('isEmpty is true when notification list is empty', async () => {
        getUnreadCount.mockResolvedValue({ success: true, data: { unreadCount: 0 } });
        getMyNotifications.mockResolvedValue({ success: true, data: [] });
        const el = createComponent();
        await Promise.resolve();
        await el.togglePanel();
        await Promise.resolve();
        expect(el.isEmpty).toBe(true);
    });
});

describe('oneopsNotificationBell — getRelativeTime', () => {
    it('returns empty string for null timestamp', () => {
        getUnreadCount.mockResolvedValue({ success: true, data: { unreadCount: 0 } });
        const el = createComponent();
        expect(el.getRelativeTime(null)).toBe('');
    });

    it('returns "just now" for recent timestamp', () => {
        getUnreadCount.mockResolvedValue({ success: true, data: { unreadCount: 0 } });
        const el = createComponent();
        const ts = new Date(Date.now() - 30000).toISOString();
        expect(el.getRelativeTime(ts)).toBe('just now');
    });

    it('returns minutes ago for < 1 hour', () => {
        getUnreadCount.mockResolvedValue({ success: true, data: { unreadCount: 0 } });
        const el = createComponent();
        const ts = new Date(Date.now() - 5 * 60 * 1000).toISOString();
        expect(el.getRelativeTime(ts)).toBe('5m ago');
    });

    it('returns hours ago for < 1 day', () => {
        getUnreadCount.mockResolvedValue({ success: true, data: { unreadCount: 0 } });
        const el = createComponent();
        const ts = new Date(Date.now() - 3 * 3600 * 1000).toISOString();
        expect(el.getRelativeTime(ts)).toBe('3h ago');
    });

    it('returns days ago for >= 1 day', () => {
        getUnreadCount.mockResolvedValue({ success: true, data: { unreadCount: 0 } });
        const el = createComponent();
        const ts = new Date(Date.now() - 2 * 86400 * 1000).toISOString();
        expect(el.getRelativeTime(ts)).toBe('2d ago');
    });
});

describe('oneopsNotificationBell — handleNotifClick', () => {
    it('marks notification as read and decrements count', async () => {
        getUnreadCount.mockResolvedValue({ success: true, data: { unreadCount: 2 } });
        getMyNotifications.mockResolvedValue({ success: true, data: SAMPLE_NOTIFICATIONS });
        markAsRead.mockResolvedValue({ success: true });
        const el = createComponent();
        await Promise.resolve();
        await el.togglePanel();
        await Promise.resolve();
        await el.handleNotifClick({ currentTarget: { dataset: { id: 'n1' } } });
        expect(markAsRead).toHaveBeenCalledWith({ notificationIds: ['n1'] });
        const updatedNotif = el.notifications.find(n => n.Id === 'n1');
        expect(updatedNotif.Is_Read__c).toBe(true);
        expect(updatedNotif.cssClass).toContain('notif-read');
    });
});

describe('oneopsNotificationBell — markAllRead', () => {
    it('marks all unread notifications as read', async () => {
        getUnreadCount.mockResolvedValue({ success: true, data: { unreadCount: 2 } });
        getMyNotifications.mockResolvedValue({ success: true, data: SAMPLE_NOTIFICATIONS });
        markAsRead.mockResolvedValue({ success: true });
        const el = createComponent();
        await Promise.resolve();
        await el.togglePanel();
        await Promise.resolve();
        await el.markAllRead();
        expect(markAsRead).toHaveBeenCalledWith({ notificationIds: ['n1', 'n3'] });
        expect(el.unreadCount).toBe(0);
        el.notifications.forEach(n => {
            expect(n.Is_Read__c).toBe(true);
        });
    });

    it('does nothing when all notifications are already read', async () => {
        const allRead = SAMPLE_NOTIFICATIONS.map(n => ({ ...n, Is_Read__c: true }));
        getUnreadCount.mockResolvedValue({ success: true, data: { unreadCount: 0 } });
        getMyNotifications.mockResolvedValue({ success: true, data: allRead });
        markAsRead.mockResolvedValue({ success: true });
        const el = createComponent();
        await Promise.resolve();
        await el.togglePanel();
        await Promise.resolve();
        await el.markAllRead();
        expect(markAsRead).not.toHaveBeenCalled();
    });
});
