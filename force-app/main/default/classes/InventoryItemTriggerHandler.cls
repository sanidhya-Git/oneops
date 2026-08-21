/**
 * Inventory Item Trigger Handler — stock status transitions and low-stock alerts.
 */
public with sharing class InventoryItemTriggerHandler {

    public void onBeforeInsert(List<Inventory_Item__c> newItems) {
        for (Inventory_Item__c item : newItems) {
            if (String.isBlank(item.Status__c)) item.Status__c = 'Active';
            if (item.Current_Stock__c == null)  item.Current_Stock__c = 0;
            if (item.Reserved_Stock__c == null) item.Reserved_Stock__c = 0;
            if (item.Reorder_Point__c == null)  item.Reorder_Point__c = 0;
            if (item.Reorder_Quantity__c == null) item.Reorder_Quantity__c = 10;
        }
    }

    public void onAfterUpdate(List<Inventory_Item__c> newItems, Map<Id, Inventory_Item__c> oldMap) {
        List<Id> lowStockItems = new List<Id>();

        for (Inventory_Item__c item : newItems) {
            Inventory_Item__c old = oldMap.get(item.Id);
            // Fired when crossing the reorder threshold in the downward direction
            if (item.Is_Low_Stock__c && !old.Is_Low_Stock__c) {
                lowStockItems.add(item.Id);
            }
        }

        if (!lowStockItems.isEmpty()) {
            List<Inventory_Item__c> details = [
                SELECT Id, Name, Current_Stock__c, Reorder_Point__c
                FROM Inventory_Item__c WHERE Id IN :lowStockItems
            ];
            for (Inventory_Item__c item : details) {
                NotificationService.notifyLowStock(item.Id, item.Name, item.Current_Stock__c, item.Reorder_Point__c);
            }
        }
    }
}
