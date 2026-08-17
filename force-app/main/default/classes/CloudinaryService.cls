/**
 * CloudinaryService — file upload and URL generation via Cloudinary REST API.
 * Named Credential: OneOps_Cloudinary
 * Used for: Employee photos, document attachments, product images for Inventory.
 */
public with sharing class CloudinaryService {

    private static final String NC_BASE = 'callout:OneOps_Cloudinary';
    private static final String UPLOAD  = '/image/upload';
    private static final String VIDEO   = '/video/upload';
    private static final String RAW     = '/raw/upload';

    /* ─── Upload base64-encoded file ─────────────────────────────── */

    @AuraEnabled
    public static OneOpsResponseWrapper uploadFile(String base64Data, String fileName,
                                                    String folder, String resourceType) {
        try {
            if (String.isBlank(base64Data)) {
                return OneOpsResponseWrapper.error('No file data provided.',
                    OneOpsException.ERR_VALIDATION, 400);
            }

            String endpoint;
            switch on (resourceType != null ? resourceType.toLowerCase() : 'image') {
                when 'video' { endpoint = NC_BASE + VIDEO; }
                when 'raw'   { endpoint = NC_BASE + RAW; }
                when else    { endpoint = NC_BASE + UPLOAD; }
            }

            // Cloudinary multipart form — simplified as JSON (requires upload preset configured for unsigned)
            Map<String, Object> payload = new Map<String, Object>{
                'file'        => 'data:application/octet-stream;base64,' + base64Data,
                'folder'      => (String.isBlank(folder) ? 'oneops' : 'oneops/' + folder),
                'public_id'   => fileName.substringBeforeLast('.') + '_' + System.currentTimeMillis()
            };

            HttpRequest req = new HttpRequest();
            req.setEndpoint(endpoint);
            req.setMethod('POST');
            req.setHeader('Content-Type', 'application/json');
            req.setTimeout(30000);
            req.setBody(JSON.serialize(payload));

            HttpResponse res = new Http().send(req);
            if (res.getStatusCode() != 200) {
                return OneOpsResponseWrapper.error('Cloudinary upload failed: ' + res.getStatusCode(),
                    OneOpsException.ERR_CALLOUT, res.getStatusCode());
            }

            Map<String, Object> result = (Map<String, Object>) JSON.deserializeUntyped(res.getBody());
            OneOpsLogger.audit('CloudinaryService', 'Uploaded: ' + result.get('secure_url'));
            return OneOpsResponseWrapper.success(result);

        } catch (Exception e) {
            OneOpsLogger.error('CloudinaryService.uploadFile', e.getMessage());
            return OneOpsResponseWrapper.error(e.getMessage(), OneOpsException.ERR_CALLOUT, 500);
        }
    }

    /**
     * Generate a transformation URL (resize, crop, format convert).
     */
    @AuraEnabled(cacheable=true)
    public static String getTransformedUrl(String publicId, Integer width, Integer height, String cropMode) {
        // Cloudinary transformation URL format: /c_fill,w_200,h_200/publicId
        String transform = 'c_' + (cropMode != null ? cropMode : 'fill')
            + (width  != null ? ',w_' + width  : '')
            + (height != null ? ',h_' + height : '');
        // URL is constructed at runtime from org's Cloudinary cloud name configured via Custom Setting
        Cloudinary_Config__c cfg = Cloudinary_Config__c.getInstance();
        if (cfg == null || String.isBlank(cfg.Cloud_Name__c)) return null;
        return 'https://res.cloudinary.com/' + cfg.Cloud_Name__c + '/image/upload/' + transform + '/' + publicId;
    }
}
