@IsTest
private class InventoryServiceTest {

    private static Warehouse__c makeWarehouse() {
        Warehouse__c w = new Warehouse__c(Name = 'Main Warehouse', Location__c = 'SF');
        insert w;
        return w;
    }

    private static Inventory_Item__c makeItem(Id warehouseId, Integer qty, Integer reorderPt) {
        return new Inventory_Item__c(
            Name            = 'Test Item ' + Crypto.getRandomInteger(),
            SKU__c          = 'SKU-' + Crypto.getRandomInteger(),
            Category__c     = 'Electronics',
            Warehouse__c    = warehouseId,
            Quantity_On_Hand__c = qty,
            Reorder_Point__c    = reorderPt,
            Unit_Cost__c        = 25.00,
            Unit_Price__c       = 49.99
        );
    }

    /* ─── getInventoryItems ──────────────────────────────────────── */

    @IsTest
    static void testGetInventoryItems_returnsAll() {
        Warehouse__c w = makeWarehouse();
        List<Inventory_Item__c> items = new List<Inventory_Item__c>();
        for (Integer i = 0; i < 3; i++) items.add(makeItem(w.Id, 100, 10));
        insert items;

        Test.startTest();
        OneOpsResponseWrapper result = InventoryService.getInventoryItems(null, null, false, 1, 10);
        Test.stopTest();

        System.assert(result.success);
        System.assert(result.totalRecords >= 3);
    }

    @IsTest
    static void testGetInventoryItems_lowStockFilter() {
        Warehouse__c w = makeWarehouse();
        Inventory_Item__c lowItem = makeItem(w.Id, 2, 10);
        Inventory_Item__c okItem  = makeItem(w.Id, 100, 10);
        insert new List<Inventory_Item__c>{ lowItem, okItem };

        Test.startTest();
        OneOpsResponseWrapper result = InventoryService.getInventoryItems(null, null, true, 1, 10);
        Test.stopTest();

        System.assert(result.success);
        List<Object> data = (List<Object>) result.data;
        System.assert(data.size() >= 1, 'Should return at least 1 low-stock item');
    }

    /* ─── adjustStock ────────────────────────────────────────────── */

    @IsTest
    static void testAdjustStock_positiveAdjustment_increasesQty() {
        Warehouse__c w = makeWarehouse();
        Inventory_Item__c item = makeItem(w.Id, 50, 10);
        insert item;

        Test.startTest();
        OneOpsResponseWrapper result = InventoryService.adjustStock(
            item.Id, 20, 'Purchase', 'Test restock', null
        );
        Test.stopTest();

        System.assert(result.success);
        Inventory_Item__c updated = [SELECT Quantity_On_Hand__c FROM Inventory_Item__c WHERE Id = :item.Id];
        System.assertEquals(70, updated.Quantity_On_Hand__c);
    }

    @IsTest
    static void testAdjustStock_negativeAdjustmentBelowZero_returnsError() {
        Warehouse__c w = makeWarehouse();
        Inventory_Item__c item = makeItem(w.Id, 5, 10);
        insert item;

        Test.startTest();
        OneOpsResponseWrapper result = InventoryService.adjustStock(
            item.Id, -10, 'Sale', 'Customer order', null
        );
        Test.stopTest();

        System.assert(!result.success, 'Should fail: quantity would go negative');
    }

    @IsTest
    static void testAdjustStock_createsStockTransactionRecord() {
        Warehouse__c w = makeWarehouse();
        Inventory_Item__c item = makeItem(w.Id, 100, 20);
        insert item;

        Test.startTest();
        InventoryService.adjustStock(item.Id, 30, 'Purchase', 'Supplier delivery', null);
        Test.stopTest();

        List<Stock_Transaction__c> txns = [
            SELECT Quantity__c, Transaction_Type__c
            FROM Stock_Transaction__c
            WHERE Item__c = :item.Id
        ];
        System.assertEquals(1, txns.size());
        System.assertEquals(30, txns[0].Quantity__c);
        System.assertEquals('Purchase', txns[0].Transaction_Type__c);
    }

    /* ─── getWarehouses ──────────────────────────────────────────── */

    @IsTest
    static void testGetWarehouses_returnsList() {
        insert makeWarehouse();

        Test.startTest();
        OneOpsResponseWrapper result = InventoryService.getWarehouses();
        Test.stopTest();

        System.assert(result.success);
        List<Object> warehouses = (List<Object>) result.data;
        System.assert(warehouses.size() >= 1);
    }
}
