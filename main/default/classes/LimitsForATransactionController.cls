public with sharing class LimitsForATransactionController {
    
    @AuraEnabled(cacheable=true)
    public static List<OrgLimitWrapper> getOrgLimits() {
        Decimal threshold = getThreshold() / 100; 
        Map<String, System.OrgLimit> systemLimits = System.OrgLimits.getMap();
        List<OrgLimitWrapper> limits = new List<OrgLimitWrapper>();
        
        for (String key : systemLimits.keySet()) {
            System.OrgLimit orgLimit = systemLimits.get(key);
            if (orgLimit.getLimit() <= 0) continue;
            
            Decimal usageRatio = orgLimit.getValue() / (Decimal)orgLimit.getLimit();
            Decimal usagePercentage = (usageRatio * 100).setScale(2);
            
            limits.add(new OrgLimitWrapper(
                key,
                orgLimit.getValue(),
                orgLimit.getLimit(),
                usagePercentage
            ));
            
            if (usageRatio.setScale(2) >= threshold.setScale(2)) {
                sendLimitNotification(key, orgLimit.getValue(), orgLimit.getLimit(), threshold);
            }
        }
        return limits;
    }
    
    private static void sendLimitNotification(String limitName, Integer used, Integer max, Decimal threshold) {
        try {
            CustomNotificationType notificationType = [
                SELECT Id FROM CustomNotificationType 
                WHERE DeveloperName = 'Org_Limit_Alerts'
                LIMIT 1
            ];
            
            Set<String> recipientIds = new Set<String>();
            for (User activeUser : [SELECT Id FROM User 
                                   WHERE IsActive = true
                                   LIMIT 1000]) { 
                recipientIds.add(activeUser.Id);
            }
            
            if (!recipientIds.isEmpty()) {
                String title = '⚠️ Critical System Limit Alert: ' + '\n' + limitName;
                String body = 
                    'Your Salesforce org is approaching a critical system limit:\n\n' +
                    '• Usage: ' + used + '/' + max + ' (' + 
                    (used/(Decimal)max*100).setScale(2) + '%)\n' +
                    '• Alert Generated On : ' + System.now().format('yyyy-MM-dd HH:mm z') + '\n' +
                    '• Organization: ' + UserInfo.getOrganizationName() + '\n\n';

                Messaging.CustomNotification notification = new Messaging.CustomNotification();
                notification.setTitle(title);
                notification.setBody(body);
                notification.setNotificationTypeId(notificationType.Id);
                notification.setTargetId(UserInfo.getOrganizationId()); 
                notification.send(recipientIds);
            }
            
        } catch (Exception e) {
            System.debug('Error: ' + e.getMessage() + '\n' + e.getStackTraceString());
        }
    }
    
    private static Decimal getThreshold() {
        return Limit_Threshold__mdt.getInstance('DefaultThreshold').Threshold_Percentage__c;
    }

    public class OrgLimitWrapper {
        @AuraEnabled public String name;
        @AuraEnabled public Integer used;
        @AuraEnabled public Integer max;
        @AuraEnabled public Decimal percentUsed;
        
        public OrgLimitWrapper(String name, Integer used, Integer max, Decimal percentUsed) {
            this.name = name;
            this.used = used;
            this.max = max;
            this.percentUsed = percentUsed.setScale(2);
        }
    }
}