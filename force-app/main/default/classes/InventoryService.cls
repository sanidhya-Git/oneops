/**
 * Inventory Service — Stock tracking, warehouse management, AI reorder intelligence.
 * Every stock movement creates an immutable Stock_Transaction__c record.
 */
public with sharing class InventoryService {

    private static final String MODULE = OneOpsConstants.MODULE_INVENTORY;

    // ── Item Retrieval ─────────────────────────────────────────────────────

    public static OneOpsResponseWrapper getInventoryItems(Integer pageNum, Integer pageSize,
                                                           String category, String warehouseId, Boolean lowStockOnly) {
        try {
            OneopsSecurity.requireRead(Inventory_Item__c.SObjectType);
            Integer offset = (pageNum - 1) * pageSize;

            String q = 'SELECT Id, Name, SKU__c, Barcode__c, Category__c, ' +
                       'Warehouse__c, Warehouse__r.Name, Primary_Vendor__c, Primary_Vendor__r.Name, ' +
                       'Current_Stock__c, Reserved_Stock__c, Available_Stock__c, ' +
                       'Reorder_Point__c, Reorder_Quantity__c, Is_Low_Stock__c, ' +
                       'Unit_Cost__c, Selling_Price__c, Unit_of_Measure__c, Status__c ' +
                       'FROM Inventory_Item__c WHERE Id != null ';

            if (String.isNotBlank(category)) {
                q += 'AND Category__c = \'' + OneopsSecurity.sanitise(category) + '\' ';
            }
            if (String.isNotBlank(warehouseId)) {
                q += 'AND Warehouse__c = \'' + OneopsSecurity.sanitise(warehouseId) + '\' ';
            }
            if (lowStockOnly == true) {
                q += 'AND Is_Low_Stock__c = true ';
            }
            q += 'ORDER BY Name ASC LIMIT :pageSize OFFSET :offset';

            List<Inventory_Item__c> items = Database.query(q);

            String countQ = 'SELECT COUNT() FROM Inventory_Item__c WHERE Id != null';
            if (String.isNotBlank(category)) countQ += ' AND Category__c = \'' + OneopsSecurity.sanitise(category) + '\'';
            if (lowStockOnly == true)        countQ += ' AND Is_Low_Stock__c = true';
            Integer total = Database.countQuery(countQ);

            return OneOpsResponseWrapper.paginated(items, total, pageSize, pageNum).withModule(MODULE);

        } catch (OneOpsException ex) {
            OneOpsLogger.error(MODULE, 'getInventoryItems failed', ex);
            return OneOpsResponseWrapper.fromException(ex);
        }
    }

    public static OneOpsResponseWrapper getItemById(Id itemId) {
        try {
            OneopsSecurity.requireRead(Inventory_Item__c.SObjectType);
            List<Inventory_Item__c> items = [
                SELECT Id, Name, SKU__c, Barcode__c, Category__c, Description__c,
                       Warehouse__c, Warehouse__r.Name, Primary_Vendor__c, Primary_Vendor__r.Name,
                       Current_Stock__c, Reserved_Stock__c, Available_Stock__c,
                       Reorder_Point__c, Reorder_Quantity__c, Is_Low_Stock__c,
                       Unit_Cost__c, Selling_Price__c, Unit_of_Measure__c, Status__c
                FROM Inventory_Item__c WHERE Id = :itemId WITH USER_MODE LIMIT 1
            ];
            if (items.isEmpty()) throw OneOpsException.notFound('Inventory Item', itemId);

            // Last 10 transactions
            List<Stock_Transaction__c> recentTx = [
                SELECT Id, Name, Transaction_Type__c, Quantity__c, Reference__c,
                       Performed_By__c, Performed_By__r.Name, CreatedDate
                FROM Stock_Transaction__c
                WHERE Inventory_Item__c = :itemId
                WITH USER_MODE ORDER BY CreatedDate DESC LIMIT 10
            ];

            return OneOpsResponseWrapper.ok(new Map<String, Object>{
                'item'               => items[0],
                'recentTransactions' => recentTx
            }).withModule(MODULE);

        } catch (OneOpsException ex) {
            return OneOpsResponseWrapper.fromException(ex);
        }
    }

    // ── Stock Adjustment ───────────────────────────────────────────────────

    public static OneOpsResponseWrapper adjustStock(Id itemId, String transactionType,
                                                     Decimal quantity, String reference, String notes) {
        try {
            OneopsSecurity.requireUpdate(Inventory_Item__c.SObjectType);
            OneopsSecurity.requireCreate(Stock_Transaction__c.SObjectType);

            if (quantity <= 0) {
                throw OneOpsException.validation('quantity', 'Quantity must be greater than zero.');
            }

            List<Inventory_Item__c> items = [
                SELECT Id, Name, Current_Stock__c, Reorder_Point__c, Reorder_Quantity__c
                FROM Inventory_Item__c WHERE Id = :itemId WITH USER_MODE LIMIT 1
            ];
            if (items.isEmpty()) throw OneOpsException.notFound('Inventory Item', itemId);
            Inventory_Item__c item = items[0];

            // Determine stock change direction
            Decimal newStock = item.Current_Stock__c != null ? item.Current_Stock__c : 0;
            Set<String> addTypes = new Set<String>{'Receipt', 'Transfer In', 'Adjustment Positive', 'Return'};
            Set<String> subTypes = new Set<String>{'Issue', 'Transfer Out', 'Adjustment Negative', 'Damaged'};

            if (addTypes.contains(transactionType)) {
                newStock += quantity;
            } else if (subTypes.contains(transactionType)) {
                if (newStock < quantity) {
                    throw OneOpsException.validation('quantity',
                        'Cannot issue more than available stock. Available: ' + newStock + ', Requested: ' + quantity);
                }
                newStock -= quantity;
            } else {
                throw OneOpsException.validation('transactionType', 'Unknown transaction type: ' + transactionType);
            }

            // Create immutable transaction record
            Stock_Transaction__c tx = new Stock_Transaction__c(
                Inventory_Item__c = itemId,
                Transaction_Type__c = transactionType,
                Quantity__c       = quantity,
                Reference__c      = reference,
                Notes__c          = notes,
                Performed_By__c   = UserInfo.getUserId()
            );

            // Update item stock
            Inventory_Item__c toUpdate = new Inventory_Item__c(Id = itemId, Current_Stock__c = newStock);
            if (newStock == 0) toUpdate.Status__c = 'Out of Stock';
            else if (newStock < item.Reorder_Point__c) toUpdate.Status__c = 'Active';

            insert tx;
            update toUpdate;

            // Fire reorder alert if needed
            if (newStock < item.Reorder_Point__c && newStock > 0) {
                NotificationService.notifyLowStock(itemId, item.Name, newStock, item.Reorder_Point__c);
            }

            OneOpsLogger.audit(MODULE, 'STOCK_ADJUST', itemId, 'Inventory_Item__c',
                transactionType + ': ' + quantity + ' units. New stock: ' + newStock + '. Ref: ' + reference);

            return OneOpsResponseWrapper.ok(new Map<String, Object>{
                'transactionId' => tx.Id,
                'newStock'      => newStock,
                'isLowStock'    => newStock < item.Reorder_Point__c
            }, 'Stock adjusted.').withModule(MODULE);

        } catch (OneOpsException ex) {
            OneOpsLogger.error(MODULE, 'adjustStock failed for ' + itemId, ex);
            return OneOpsResponseWrapper.fromException(ex);
        }
    }

    // ── AI Reorder Suggestions ─────────────────────────────────────────────

    public static OneOpsResponseWrapper getLowStockWithAISuggestions() {
        try {
            List<Inventory_Item__c> lowStock = [
                SELECT Id, Name, SKU__c, Current_Stock__c, Reorder_Point__c,
                       Reorder_Quantity__c, Primary_Vendor__c, Primary_Vendor__r.Name,
                       Unit_Cost__c, Category__c
                FROM Inventory_Item__c
                WHERE Is_Low_Stock__c = true AND Status__c = 'Active'
                WITH USER_MODE ORDER BY Available_Stock__c ASC LIMIT 50
            ];

            if (lowStock.isEmpty()) {
                return OneOpsResponseWrapper.ok(new List<Object>(), 'No low stock items.').withModule(MODULE);
            }

            // Build AI payload with all low stock items for batch analysis
            List<Map<String, Object>> itemPayloads = new List<Map<String, Object>>();
            for (Inventory_Item__c item : lowStock) {
                itemPayloads.add(new Map<String, Object>{
                    'itemId'          => item.Id,
                    'name'            => item.Name,
                    'sku'             => item.SKU__c,
                    'currentStock'    => item.Current_Stock__c,
                    'reorderPoint'    => item.Reorder_Point__c,
                    'reorderQuantity' => item.Reorder_Quantity__c,
                    'category'        => item.Category__c,
                    'unitCost'        => item.Unit_Cost__c
                });
            }

            Map<String, Object> aiPayload = new Map<String, Object>{
                'action' => 'reorder_suggestions',
                'items'  => itemPayloads
            };

            AIEngineService.AIResponse aiResp = AIEngineService.callAIEngine(aiPayload);

            return OneOpsResponseWrapper.ok(new Map<String, Object>{
                'lowStockItems'   => lowStock,
                'aiSuggestions'   => aiResp.success ? aiResp.data : null,
                'aiProvider'      => aiResp.provider
            }).withModule(MODULE).withAIProvider(aiResp.provider);

        } catch (OneOpsException ex) {
            return OneOpsResponseWrapper.fromException(ex);
        }
    }

    // ── Warehouse Management ───────────────────────────────────────────────

    public static OneOpsResponseWrapper getWarehouses() {
        try {
            OneopsSecurity.requireRead(Warehouse__c.SObjectType);
            List<Warehouse__c> warehouses = [
                SELECT Id, Name, Warehouse_Code__c, Address__c,
                       Manager__c, Manager__r.Name,
                       Total_Capacity__c, Current_Occupancy__c, Is_Active__c
                FROM Warehouse__c WHERE Is_Active__c = true WITH USER_MODE ORDER BY Name
            ];
            return OneOpsResponseWrapper.ok(warehouses).withModule(MODULE);
        } catch (OneOpsException ex) {
            return OneOpsResponseWrapper.fromException(ex);
        }
    }
}
