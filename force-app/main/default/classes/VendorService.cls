/**
 * Vendor Service — Vendor profiles, purchase order lifecycle, scorecards, and AI evaluations.
 */
public with sharing class VendorService {

    private static final String MODULE = OneOpsConstants.MODULE_VENDOR;

    // ── Vendor CRUD ────────────────────────────────────────────────────────

    public static OneOpsResponseWrapper getVendors(String status, String vendorType, Integer pageNum, Integer pageSize) {
        try {
            OneopsSecurity.requireRead(Vendor__c.SObjectType);
            Integer offset = (pageNum - 1) * pageSize;

            String q = 'SELECT Id, Name, Vendor_Code__c, Vendor_Type__c, Status__c, ' +
                       'Contact_Name__c, Email__c, Phone__c, Country__c, ' +
                       'Payment_Terms__c, Credit_Limit__c, Total_Spend__c, ' +
                       'AI_Performance_Score__c, On_Time_Delivery_Rate__c, Contract_Expiry_Date__c ' +
                       'FROM Vendor__c WHERE Id != null ';
            if (String.isNotBlank(status)) q += 'AND Status__c = \'' + OneopsSecurity.sanitise(status) + '\' ';
            if (String.isNotBlank(vendorType)) q += 'AND Vendor_Type__c = \'' + OneopsSecurity.sanitise(vendorType) + '\' ';
            q += 'ORDER BY Name ASC LIMIT :pageSize OFFSET :offset';

            List<Vendor__c> vendors = Database.query(q);
            Integer total = [SELECT COUNT() FROM Vendor__c];

            return OneOpsResponseWrapper.paginated(vendors, total, pageSize, pageNum).withModule(MODULE);

        } catch (OneOpsException ex) {
            return OneOpsResponseWrapper.fromException(ex);
        }
    }

    public static OneOpsResponseWrapper createVendor(Map<String, Object> fields) {
        try {
            OneopsSecurity.requireCreate(Vendor__c.SObjectType);

            if (String.isBlank((String) fields.get('name'))) {
                throw OneOpsException.validation('name', 'Vendor name is required.');
            }

            // Check for duplicate vendor name
            List<Vendor__c> existing = [
                SELECT Id FROM Vendor__c WHERE Name = :(String)fields.get('name') WITH USER_MODE LIMIT 1
            ];
            if (!existing.isEmpty()) {
                throw OneOpsException.duplicate('Vendor', 'Name', (String) fields.get('name'));
            }

            Vendor__c vendor = new Vendor__c(
                Name                = (String)  fields.get('name'),
                Vendor_Code__c      = generateVendorCode(),
                Vendor_Type__c      = (String)  fields.get('vendorType'),
                Status__c           = 'Active',
                Contact_Name__c     = (String)  fields.get('contactName'),
                Email__c            = (String)  fields.get('email'),
                Phone__c            = (String)  fields.get('phone'),
                Website__c          = (String)  fields.get('website'),
                Country__c          = (String)  fields.get('country'),
                Payment_Terms__c    = (String)  fields.get('paymentTerms'),
                Tax_Registration__c = (String)  fields.get('taxRegistration'),
                Notes__c            = (String)  fields.get('notes')
            );

            if (fields.containsKey('creditLimit')) {
                vendor.Credit_Limit__c = Decimal.valueOf(String.valueOf(fields.get('creditLimit')));
            }
            if (fields.containsKey('contractExpiry')) {
                vendor.Contract_Expiry_Date__c = Date.valueOf((String) fields.get('contractExpiry'));
            }

            insert vendor;

            OneOpsLogger.audit(MODULE, OneOpsConstants.AUDIT_CREATE, vendor.Id, 'Vendor__c',
                'Vendor created: ' + vendor.Name + ' (Code: ' + vendor.Vendor_Code__c + ')');

            return OneOpsResponseWrapper.created(vendor).withModule(MODULE);

        } catch (OneOpsException ex) {
            OneOpsLogger.error(MODULE, 'createVendor failed', ex);
            return OneOpsResponseWrapper.fromException(ex);
        }
    }

    // ── Purchase Order Management ──────────────────────────────────────────

    public static OneOpsResponseWrapper createPurchaseOrder(Map<String, Object> fields) {
        try {
            OneopsSecurity.requireCreate(Purchase_Order__c.SObjectType);

            if (fields.get('vendorId') == null) {
                throw OneOpsException.validation('vendorId', 'Vendor is required for purchase order.');
            }

            Purchase_Order__c po = new Purchase_Order__c(
                Vendor__c           = (Id) fields.get('vendorId'),
                Status__c           = OneOpsConstants.STATUS_DRAFT,
                Order_Date__c       = Date.today(),
                Expected_Date__c    = fields.containsKey('expectedDate') ? Date.valueOf((String) fields.get('expectedDate')) : Date.today().addDays(14),
                Shipped_To_Warehouse__c = (Id) fields.get('warehouseId'),
                Notes__c            = (String) fields.get('notes')
            );

            insert po;

            // Create PO line items if provided
            if (fields.containsKey('lineItems')) {
                createPOLines(po.Id, (List<Object>) fields.get('lineItems'));
            }

            OneOpsLogger.audit(MODULE, OneOpsConstants.AUDIT_CREATE, po.Id, 'Purchase_Order__c',
                'PO created for vendor: ' + fields.get('vendorId'));

            return OneOpsResponseWrapper.created(po).withModule(MODULE);

        } catch (OneOpsException ex) {
            OneOpsLogger.error(MODULE, 'createPurchaseOrder failed', ex);
            return OneOpsResponseWrapper.fromException(ex);
        }
    }

    public static OneOpsResponseWrapper submitPOForApproval(Id poId) {
        try {
            List<Purchase_Order__c> pos = [
                SELECT Id, Status__c, Total_Amount__c FROM Purchase_Order__c WHERE Id = :poId WITH USER_MODE LIMIT 1
            ];
            if (pos.isEmpty()) throw OneOpsException.notFound('Purchase Order', poId);
            if (pos[0].Status__c != 'Draft') {
                throw OneOpsException.validation('status', 'Only draft POs can be submitted for approval.');
            }

            update new Purchase_Order__c(Id = poId, Status__c = 'Pending Approval');

            Approval.ProcessSubmitRequest req = new Approval.ProcessSubmitRequest();
            req.setObjectId(poId);
            req.setSubmitterId(UserInfo.getUserId());
            req.setComments('PO submitted for approval. Amount: ' + pos[0].Total_Amount__c);
            Approval.process(req);

            OneOpsLogger.audit(MODULE, 'PO_SUBMIT', poId, 'Purchase_Order__c', 'PO submitted for approval.');
            return OneOpsResponseWrapper.ok(null, 'Purchase order submitted for approval.').withModule(MODULE);

        } catch (OneOpsException ex) {
            return OneOpsResponseWrapper.fromException(ex);
        }
    }

    public static OneOpsResponseWrapper receivePOItems(Id poId, Map<Id, Decimal> itemQuantities) {
        try {
            OneopsSecurity.requireUpdate(Purchase_Order_Line__c.SObjectType);

            List<Purchase_Order_Line__c> lines = [
                SELECT Id, Inventory_Item__c, Quantity__c, Received_Quantity__c, Unit_Price__c
                FROM Purchase_Order_Line__c WHERE Purchase_Order__c = :poId WITH USER_MODE
            ];

            List<Purchase_Order_Line__c> linesToUpdate = new List<Purchase_Order_Line__c>();
            List<Stock_Transaction__c> txList = new List<Stock_Transaction__c>();

            for (Purchase_Order_Line__c line : lines) {
                if (!itemQuantities.containsKey(line.Id)) continue;
                Decimal received = itemQuantities.get(line.Id);

                linesToUpdate.add(new Purchase_Order_Line__c(
                    Id = line.Id,
                    Received_Quantity__c = (line.Received_Quantity__c != null ? line.Received_Quantity__c : 0) + received
                ));

                // Create stock receipt transaction
                txList.add(new Stock_Transaction__c(
                    Inventory_Item__c   = line.Inventory_Item__c,
                    Transaction_Type__c = 'Receipt',
                    Quantity__c         = received,
                    Unit_Cost__c        = line.Unit_Price__c,
                    Reference__c        = 'PO Receipt',
                    Performed_By__c     = UserInfo.getUserId()
                ));
            }

            update linesToUpdate;
            insert txList;

            // Update PO status
            update new Purchase_Order__c(Id = poId, Status__c = 'Received');

            OneOpsLogger.audit(MODULE, 'PO_RECEIVE', poId, 'Purchase_Order__c', 'PO items received.');
            return OneOpsResponseWrapper.ok(null, 'Items received and stock updated.').withModule(MODULE);

        } catch (OneOpsException ex) {
            return OneOpsResponseWrapper.fromException(ex);
        }
    }

    // ── AI Vendor Scorecard ────────────────────────────────────────────────

    public static OneOpsResponseWrapper getVendorScorecard(Id vendorId) {
        try {
            List<Vendor__c> vendors = [
                SELECT Id, Name, On_Time_Delivery_Rate__c, Total_Spend__c, AI_Performance_Score__c,
                       Contract_Expiry_Date__c
                FROM Vendor__c WHERE Id = :vendorId WITH USER_MODE LIMIT 1
            ];
            if (vendors.isEmpty()) throw OneOpsException.notFound('Vendor', vendorId);

            Integer totalPOs   = [SELECT COUNT() FROM Purchase_Order__c WHERE Vendor__c = :vendorId WITH USER_MODE];
            Integer onTimePOs  = [SELECT COUNT() FROM Purchase_Order__c WHERE Vendor__c = :vendorId AND Status__c = 'Delivered' WITH USER_MODE];

            Map<String, Object> aiPayload = new Map<String, Object>{
                'action'            => 'vendor_scorecard',
                'vendorId'          => vendorId,
                'vendorName'        => vendors[0].Name,
                'totalPOs'          => totalPOs,
                'onTimePOs'         => onTimePOs,
                'totalSpend'        => vendors[0].Total_Spend__c,
                'currentScore'      => vendors[0].AI_Performance_Score__c,
                'contractExpiry'    => String.valueOf(vendors[0].Contract_Expiry_Date__c)
            };

            AIEngineService.AIResponse aiResp = AIEngineService.callAIEngine(aiPayload);

            if (aiResp.success) {
                Decimal newScore = Decimal.valueOf(String.valueOf(aiResp.data.get('performanceScore')));
                update new Vendor__c(Id = vendorId, AI_Performance_Score__c = newScore);
            }

            return OneOpsResponseWrapper.ok(new Map<String, Object>{
                'vendor'      => vendors[0],
                'totalPOs'    => totalPOs,
                'onTimePOs'   => onTimePOs,
                'aiScorecard' => aiResp.success ? aiResp.data : null
            }).withModule(MODULE);

        } catch (OneOpsException ex) {
            return OneOpsResponseWrapper.fromException(ex);
        }
    }

    // ── Private Helpers ────────────────────────────────────────────────────

    private static String generateVendorCode() {
        Integer cnt = [SELECT COUNT() FROM Vendor__c] + 1;
        return 'VND-' + String.valueOf(cnt).leftPad(5, '0');
    }

    private static void createPOLines(Id poId, List<Object> lineItems) {
        List<Purchase_Order_Line__c> lines = new List<Purchase_Order_Line__c>();
        for (Object item : lineItems) {
            Map<String, Object> line = (Map<String, Object>) item;
            lines.add(new Purchase_Order_Line__c(
                Purchase_Order__c    = poId,
                Inventory_Item__c    = (Id)      line.get('itemId'),
                Description__c       = (String)  line.get('description'),
                Quantity__c          = Decimal.valueOf(String.valueOf(line.get('quantity'))),
                Unit_Price__c        = Decimal.valueOf(String.valueOf(line.get('unitPrice')))
            ));
        }
        if (!lines.isEmpty()) insert lines;
    }
}
