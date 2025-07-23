public with sharing class OrgLimitsController {
    public class LimitWrapper {
        @AuraEnabled public String name;
        @AuraEnabled public Integer used;
        @AuraEnabled public Integer max;

        public LimitWrapper(String n, Integer u, Integer m) {
            name = n;
            used = u;
            max = m;
        }
    }

    private static final Decimal USAGE_THRESHOLD = 10.0; 
    private static final String NOTIFICATION_TYPE = 'Org_Limit_Alerts';

    @AuraEnabled(cacheable=true)
    public static List<LimitWrapper> getOrgLimits() {
        List<LimitWrapper> result = new List<LimitWrapper>();
        Map<String, System.OrgLimit> systemLimits = System.OrgLimits.getMap();
        Set<String> trackedLimits = getTrackedLimits();

        for (String limitName : systemLimits.keySet()) {
            if (!trackedLimits.contains(limitName)) continue;

            System.OrgLimit limitRecord = systemLimits.get(limitName);
            result.add(new LimitWrapper(
                limitName,
                limitRecord.getValue(),
                limitRecord.getLimit()
            ));
        }
        return result;
    }

    @AuraEnabled
    public static void checkAndNotifyLowUsageLimits() {
        List<LimitWrapper> limits = getOrgLimits();
        Id notificationTypeId = getNotificationTypeId();

        if (notificationTypeId == null) {
            System.debug('Notification type not found');
            return;
        }

        Set<String> adminUserIds = getAdminUserIds();
        if (adminUserIds.isEmpty()) {
            System.debug('No admin users found to notify');
            return;
        }

        for (LimitWrapper currentLimit : limits) {
            if (currentLimit.max == 0) continue;

            Decimal usagePercent = (Decimal.valueOf(currentLimit.used) / Decimal.valueOf(currentLimit.max)) * 100;

            System.debug('Checking ' + currentLimit.name + ': usage = ' + usagePercent + '%');

            if (usagePercent >= USAGE_THRESHOLD) {
                sendNotification(
                    notificationTypeId,
                    formatLabel(currentLimit.name),
                    usagePercent,
                    currentLimit.used,
                    currentLimit.max,
                    adminUserIds
                );
            }
        }
    }

    private static void sendNotification(
        Id notificationTypeId,
        String limitName,
        Decimal usagePercent,
        Integer used,
        Integer max,
        Set<String> recipientIds
    ) {
        try {
            Messaging.CustomNotification notification = new Messaging.CustomNotification();
            notification.setTitle(' Hi '+ UserInfo.getFirstName() +', Low Org Limit Usage: ' + limitName);
            notification.setBody(
                limitName + ' is only ' + usagePercent.setScale(2) + '% used\n' +
                'Used: ' + used + ' of ' + max + '\n' +
                '90% or more remaining.'
            );
            notification.setNotificationTypeId(notificationTypeId);
            notification.setTargetId(UserInfo.getOrganizationId());
            notification.send(recipientIds);
        } catch (Exception e) {
            System.debug('Error sending notification: ' + e.getMessage());
        }
    }

    private static Set<String> getTrackedLimits() {
        return new Set<String>{
            'DailyApiRequests',
            'DataStorageMB',
            'FileStorageMB',
            'DailyBulkApiBatches',
            'DailyDurableStreamingApiEvents',
            'DailyStandardVolumePlatformEvents',
            'HourlyPublishedStandardVolumePlatformEvents',
            'HourlyPublishedPlatformEvents',
            'DailyDeliveredPlatformEvents',
            'PlatformEventTriggersWithParallelProcessing',
            'DailyDurableGenericStreamingApiEvents',
            'DurableStreamingApiConcurrentClients',
            'PublishCallbackUsageInApex',
            'DailyBulkV2QueryJobs',
            'DailyBulkV2QueryFileStorageMB',
            'SingleEmail',
            'MassEmail',
            'DailyMetadataRetrievesWithDependencies',
            'PermissionSets',
            'PrivateConnectOutboundCalloutHourlyLimitMB',
            'HourlyODataCallout',
            'HourlyLongTermIdMapping',
            'HourlyShortTermIdMapping',
            'HourlyDashboardRefreshes',
            'HourlyDashboardResults',
            'HourlyDashboardStatuses',
            'HourlySyncReportRuns',
            'HourlyAsyncReportRuns',
            'HourlyElevateSyncReportRuns',
            'HourlyElevateAsyncReportRuns',
            'ConcurrentSyncReportRuns',
            'ConcurrentAsyncGetReportInstances',
            'DailyAnalyticsDataflowJobExecutions',
            'DailyAnalyticsUploadedFilesSizeMB',
            'AnalyticsExternalDataSizeMB',
            'CdpAiInferenceApiMonthlyLimit',
            'DailyEinsteinDiscoveryPredictionsByCDC',
            'MonthlyEinsteinDiscoveryStoryCreation',
            'DailyEinsteinDiscoveryStoryCreation',
            'DailyEinsteinDataInsightsStoryCreation',
            'ConcurrentEinsteinDataInsightsStoryCreation',
            'ConcurrentEinsteinDiscoveryStoryCreation',
            'DailyEinsteinDiscoveryPredictAPICalls',
            'DailyEinsteinDiscoveryOptimizationJobRuns',
            'ContentDistViewLimit',
            'ContentDistBandwidthLimitMB',
            'ContentPublicationLimit',
            'MaxContentDocumentsLimit',
            'Package2VersionCreates',
            'Package2VersionCreatesWithoutValidation',
            'DailyScratchOrgs',
            'ActiveScratchOrgs',
            'HourlyTimeBasedWorkflow',
            'DailyWorkflowEmails',
            'DailyAsyncApexExecutions',
            'DailyAsyncApexTests',
            'DailyBulkApiBatches',
            'DailyGenericStreamingApiEvents',
            'StreamingApiConcurrentClients',
            'DailyStreamingApiEvents',
            'HourlyManagedContentPublicRequests',
            'DailyFunctionsApiCallLimit'
        };
    }

    private static Id getNotificationTypeId() {
        try {
            return [SELECT Id FROM CustomNotificationType 
                    WHERE DeveloperName = :NOTIFICATION_TYPE 
                    LIMIT 1].Id;
        } catch (Exception e) {
            return null;
        }
    }

    private static Set<String> getAdminUserIds() {
        Set<String> userIds = new Set<String>();
        for (User u : [SELECT Id FROM User WHERE Profile.Name = 'System Administrator' AND IsActive = true LIMIT 50]) {
            userIds.add(u.Id);
        }
        return userIds;
    }

    private static String formatLabel(String limitName) {
        limitName = limitName.replaceAll('([A-Z])', ' $1');
        limitName = limitName.replaceAll('([A-Z])([A-Z][a-z])', '$1 $2');
        limitName = limitName
            .replace('Api', 'API')
            .replace('Mb', 'MB')
            .replace('Cdp', 'CDP')
            .replace('Einstein', 'Einstein ')
            .replace('Platform', 'Platform ')
            .trim();
        return limitName;
    }
}
