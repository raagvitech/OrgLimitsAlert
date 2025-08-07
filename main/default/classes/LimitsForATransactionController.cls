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
    private static Decimal getThreshold() {
        return Limit_Threshold__mdt.getInstance('DefaultThreshold').Threshold_Percentage__c;
    }
   private static void sendLimitNotification(String limitName, Integer used, Integer max, Decimal threshold) {
    try {
        CustomNotificationType notificationType = [
            SELECT Id FROM CustomNotificationType 
            WHERE DeveloperName = 'Org_Limit_Alerts'
            LIMIT 1
        ];

        Set<String> recipientIds = new Set<String>();
        for (User activeUser : [SELECT Id FROM User WHERE IsActive = true LIMIT 1000]) {
            recipientIds.add(activeUser.Id);
        }

        if (!recipientIds.isEmpty()) {
            String category = getLimitCategory(limitName);
            String categoryLabel = getCategoryLabel(category);
            
            String title = '⚠️ Critical System Limit Alert: ' + limitName;
            String body = 
                'Your Salesforce org is approaching a critical system limit:\n\n' +
                '• Tab Category: ' + categoryLabel + '\n' +
                '• Usage: ' + used + '/' + max + ' (' + 
                (used / (Decimal)max * 100).setScale(2) + '%)\n' +
                '• Alert Time: ' + System.now().format('yyyy-MM-dd HH:mm z') + '\n' +
                '• Org: ' + UserInfo.getOrganizationName();

            Messaging.CustomNotification notification = new Messaging.CustomNotification();
            notification.setTitle(title);
            notification.setBody(body);
            notification.setNotificationTypeId(notificationType.Id);
            notification.setTargetId(UserInfo.getOrganizationId());
            notification.send(recipientIds);
        }
    } catch (Exception e) {
        System.debug('Notification Error: ' + e.getMessage());
    }
}

private static String getLimitCategory(String limitName) {
    if (limitName == null) return 'Others';
    
    String name = limitName.toLowerCase();
    
    if (name.contains('api')) return 'API';
    if (name.contains('storage') || name.contains('content')) return 'Storage';
    if (name.contains('event') || name.contains('stream')) return 'PlatformEvents';
    if (name.contains('email')) return 'Email';
    if (name.contains('dashboard') || name.contains('report')) return 'ReportsDashboards';
    if (name.contains('einstein') || name.contains('analytics')) return 'Analytics';
    if (name.contains('apex') || name.contains('workflow')) return 'AsyncApex';
    if (name.contains('metadata') || name.contains('package')) return 'MetadataDeploy';
    
    return 'Others';
}

private static String getCategoryLabel(String category) {
    switch on category {
        when 'API' { return 'API Usage'; }
        when 'Storage' { return 'Storage'; }
        when 'PlatformEvents' { return 'Platform Events'; }
        when 'Email' { return 'Email'; }
        when 'ReportsDashboards' { return 'Reports / Dashboards'; }
        when 'Analytics' { return 'Analytics'; }
        when 'AsyncApex' { return 'Async Apex'; }
        when 'MetadataDeploy' { return 'Deployments'; }
        when else { return 'Other Limits'; }
    }
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

    public class SuggestionWrapper {
        @AuraEnabled public String message;
        public SuggestionWrapper(String message) {
            this.message = message;
        }
    }

    public class ObjectCount implements Comparable {
        public String objectName;
        public Integer count;

        public ObjectCount(String objectName, Integer count) {
            this.objectName = objectName;
            this.count = count;
        }

        public Integer compareTo(Object obj) {
            ObjectCount other = (ObjectCount) obj;
            return other.count - this.count; 
        }
    }

    @AuraEnabled(cacheable=true)
    public static List<SuggestionWrapper> getLimitSuggestions(String limitName) {
        List<SuggestionWrapper> suggestions = new List<SuggestionWrapper>();
        String lowerName = limitName != null ? limitName.toLowerCase() : '';

        try {
            if (lowerName.contains('datastorage')) {
                Map<String, Schema.SObjectType> gd = Schema.getGlobalDescribe();
                List<ObjectCount> objectCounts = new List<ObjectCount>();
                Integer queriesRun = 0;

                for (String objectName : gd.keySet()) {
                    if (queriesRun >= 80) break;
                    if (!objectName.toLowerCase().endsWith('__mdt') &&
                        gd.get(objectName).getDescribe().isQueryable()) {
                        try {
                            Integer count = Database.countQuery('SELECT COUNT() FROM ' + objectName);
                            queriesRun++;
                            if (count > 0) {
                                objectCounts.add(new ObjectCount(objectName, count));
                            }
                        } catch (Exception e) {
                            continue;
                        }
                    }
                }

                objectCounts.sort();
                for (ObjectCount oc : objectCounts) {
                    suggestions.add(new SuggestionWrapper(oc.objectName + ': ' + oc.count + ' records.'));
                }

            } else if (lowerName.contains('filestorage')) {
                suggestions.add(new SuggestionWrapper('Attachments: ' + [SELECT COUNT() FROM Attachment] + '. Delete or archive large old attachments.'));
                suggestions.add(new SuggestionWrapper('ContentVersion: ' + [SELECT COUNT() FROM ContentVersion] + '. Archive unused files.'));
                suggestions.add(new SuggestionWrapper('Document: ' + [SELECT COUNT() FROM Document] + '. Remove outdated classic documents.'));

            } else if (lowerName.contains('dailybulkv2queryfilestoragemb')) {
                Integer bulkJobs = [SELECT COUNT() FROM AsyncApexJob WHERE JobType = 'BulkV2Query'];
                suggestions.add(new SuggestionWrapper('Bulk V2 Query Jobs: ' + bulkJobs + '. Delete old or failed BulkV2 jobs.'));

            } else if (lowerName.contains('contentdistviewlimit')) {
                Integer distributions = [SELECT COUNT() FROM ContentDistribution];
                suggestions.add(new SuggestionWrapper('ContentDistributions: ' + distributions + '. Expire old public sharing links to reduce views.'));

            } else if (lowerName.contains('contentdistbandwidthlimitmb')) {
                Integer dist = [SELECT COUNT() FROM ContentDistribution];
                suggestions.add(new SuggestionWrapper('Distributions: ' + dist + '. Optimize file size and sharing methods to save bandwidth.'));

            } else if (lowerName.contains('contentpublicationlimit')) {
                Integer published = [SELECT COUNT() FROM ContentVersion WHERE PublishStatus != 'U'];
                suggestions.add(new SuggestionWrapper('Published ContentVersion files: ' + published + '. Unpublish outdated files.'));

            } else if (lowerName.contains('maxcontentdocumentslimit')) {
                Integer total = [SELECT COUNT() FROM ContentDocument];
                suggestions.add(new SuggestionWrapper('ContentDocument records: ' + total + '. Consolidate duplicates or archive rarely accessed ones.'));

            } else if (lowerName.contains('hourlymanagedcontentpublicrequests')) {
                Integer total = [SELECT COUNT() FROM ContentDistribution];
                suggestions.add(new SuggestionWrapper('Public Requests via ContentDistribution: ' + total + '. Remove or expire unused public links.'));
            } else if (lowerName.contains('dailyapirequests')) {
                Integer loginHistory = [SELECT COUNT() FROM LoginHistory WHERE LoginTime = LAST_N_DAYS:1];
                Integer connectedApps = [SELECT COUNT() FROM ConnectedApplication];
                Integer namedCreds = [SELECT COUNT() FROM NamedCredential];

    suggestions.add(new SuggestionWrapper('LoginHistory: ' + loginHistory + ' logins today. Optimize frequent integrations.'));
    suggestions.add(new SuggestionWrapper('Connected Apps: ' + connectedApps + ' integrated apps. Revoke unused tokens.'));
    suggestions.add(new SuggestionWrapper('Named Credentials: ' + namedCreds + ' defined. Audit usage of scheduled jobs.'));
   suggestions.add(new SuggestionWrapper('Review Remote Site Settings manually via Setup to reduce unnecessary integrations.'));
}else if (lowerName.contains('dailybulkapibatches')) {
    Integer bulkJobsToday = [SELECT COUNT() FROM AsyncApexJob WHERE JobType = 'BulkAPIV1' AND CreatedDate = TODAY];
    Integer bulkJobsFailed = [SELECT COUNT() FROM AsyncApexJob WHERE JobType = 'BulkAPIV1' AND Status = 'Failed' AND CreatedDate = LAST_N_DAYS:7];

    suggestions.add(new SuggestionWrapper('BulkAPI Jobs today: ' + bulkJobsToday + '. Consolidate into fewer batches.'));
    suggestions.add(new SuggestionWrapper('Failed Bulk Jobs (7 days): ' + bulkJobsFailed + '. Investigate failures and retry logic.'));
}else if (lowerName.contains('dailystreamingapievents') || lowerName.contains('dailygenericstreamingapievents')) {
    Integer pushTopics = [SELECT COUNT() FROM PushTopic];
    Integer platformEvents = [SELECT COUNT() FROM EventBusSubscriber];
    suggestions.add(new SuggestionWrapper('PushTopics: ' + pushTopics + '. Remove inactive subscriptions.'));
    suggestions.add(new SuggestionWrapper('Active PlatformEvent Subscriptions: ' + platformEvents + '. Audit consumer reliability.'));
}else if (lowerName.contains('streamingapiconcurrentapiclients')) {
    Integer activeUsers = [SELECT COUNT() FROM User WHERE IsActive = true];
    Integer evtSubscriptions = [SELECT COUNT() FROM EventBusSubscriber];
    suggestions.add(new SuggestionWrapper('Active users: ' + activeUsers + '. Limit redundant listeners.'));
    suggestions.add(new SuggestionWrapper('Streaming Subscribers: ' + evtSubscriptions + '. Review concurrent CometD clients.'));
}else if (lowerName.contains('dailydurablestreamingapievents') || lowerName.contains('durablestreamingapiconcurrentclients')) {
suggestions.add(new SuggestionWrapper('Durable Subscriptions. Ensure subscribers consume in time.'));
}else if (lowerName.contains('dailydurablegenericstreamingapievents') || lowerName.contains('durablestreamingapiconcurrentclients')) {
suggestions.add(new SuggestionWrapper('Durable Generic Streaming API Events. Ensure subscribers consume in time.'));
}else if (lowerName.contains('cdpaiinterfaceapimonthlylimit')) {
suggestions.add(new SuggestionWrapper('Review Flows that invoke CDP interfaces. Use schedules instead of real-time if possible.'));
}else if (lowerName.contains('dailyeninsteindiscoverypredictapicalls')) {
   suggestions.add(new SuggestionWrapper('Check Discovery Models manually. Deactivate models that are not currently used in predictions.'));
}else if (lowerName.contains('hourlypublishedplatformevents')) {
    Datetime oneHourAgo = Datetime.now().addHours(-1);
    Integer totalEventCount = 0;
    List<String> platformEventApiNames = new List<String>{
        'MyPlatformEvent__e',
        'AnotherEvent__e'
    };
    for (String apiName : platformEventApiNames) {
            String query = 'SELECT COUNT() FROM ' + apiName + ' WHERE CreatedDate >= :oneHourAgo';
            totalEventCount += (Integer)Database.countQuery(query);
        }
    suggestions.add(new SuggestionWrapper('Published Platform Events in last hour: ' + totalEventCount +
        '. Consider reducing frequency or batch events.'));
}else if (lowerName.contains('dailydeliveredplatformevents')) {
    Integer delivered = [SELECT COUNT() FROM AsyncApexJob WHERE JobType = 'Event' AND CreatedDate = TODAY];
    suggestions.add(new SuggestionWrapper('Delivered Platform Event Jobs Today: ' + delivered +
        '. Review event subscribers and reduce complexity if needed.'));
}else if (lowerName.contains('platformeventstriggerswithparallelprocessing')) {
    suggestions.add(new SuggestionWrapper('Platform Event Triggers: Use "Serial" mode if order of delivery is important.'));
}else if (lowerName.contains('singleemail')) {
    Integer sentSingleEmailsToday = [SELECT COUNT() FROM EmailMessage WHERE CreatedDate = TODAY AND MessageIdentifier != null];
    suggestions.add(new SuggestionWrapper('Single Emails sent today: ' + sentSingleEmailsToday +
        '. Consider consolidating messages or using email templates with merge fields where applicable.'));
}else if (lowerName.contains('massemail')) {
    Integer massEmailsToday = [SELECT COUNT() FROM EmailMessage WHERE CreatedDate = TODAY AND Subject LIKE '%Mass%' AND Incoming = false];
    suggestions.add(new SuggestionWrapper('Mass Emails sent today (approximated): ' + massEmailsToday +
        '. Consider using Campaigns or external email platforms for bulk sends.'));
}else if (lowerName.contains('dailyworkflowemails')) {
    Integer workflowEmailsToday = [SELECT COUNT() FROM EmailMessage WHERE CreatedDate = TODAY AND Incoming = false AND (IsClientManaged = false OR IsClientManaged = null)];
    suggestions.add(new SuggestionWrapper('Workflow Emails sent today: ' + workflowEmailsToday +
        '. Review Workflow Rules and Flows for unnecessary or frequent email actions.'));
}else if (lowerName.contains('async')) {
    Integer jobs = [SELECT COUNT() FROM AsyncApexJob WHERE CreatedDate = LAST_N_DAYS:7];
                suggestions.add(new SuggestionWrapper('Async Jobs in last 7 days: ' + jobs + '. Review failed or long-running jobs.'));
                suggestions.add(new SuggestionWrapper('Use Queueable instead of Future where appropriate.'));
}else if (lowerName.contains('hourlydashboardrefreshes')) {
    Integer dashboardEvents = [SELECT COUNT() FROM EventLogFile 
        WHERE EventType = 'Dashboard' AND LogDate = TODAY];
    suggestions.add(new SuggestionWrapper('Dashboard events logged today: ' + dashboardEvents +
        '. Consider reducing dashboard auto-refresh frequency or scheduling refreshes.'));
}else if (lowerName.contains('hourlydashboardresults')) {
    Integer accessedDashboards = [SELECT COUNT() FROM Dashboard 
        WHERE LastReferencedDate >= :System.now().addMinutes(-60)];
    suggestions.add(new SuggestionWrapper('Dashboards accessed in last hour: ' + accessedDashboards +
        '. Encourage users to minimize frequent accesses or split large dashboards.'));
}else if (lowerName.contains('hourlydashboardstatuses')) {
    suggestions.add(new SuggestionWrapper('Hourly Dashboard Statuses: Not directly queryable. ' +
        'Monitor dashboard refresh statuses via Setup or Event Monitoring.'));
}else if (lowerName.contains('hourlysyncreportruns')) {
    Integer syncReports = [SELECT COUNT() FROM Report 
        WHERE LastRunDate >= :System.now().addMinutes(-60)];
    suggestions.add(new SuggestionWrapper('Reports run in last hour: ' + syncReports +
        '. Consider optimizing filters or scheduling reports during off-hours.'));
}else if (lowerName.contains('hourlysyncreportruns')) {
    Integer syncReports = [
        SELECT COUNT() FROM Report 
        WHERE LastRunDate >= :System.now().addMinutes(-60)
    ];
    suggestions.add(new SuggestionWrapper('Sync reports run in last hour: ' + syncReports +
        '. Consider spreading report execution or scheduling non-peak times.'));
}else if (lowerName.contains('hourlyelevatesyncreportruns')) {
    suggestions.add(new SuggestionWrapper('Hourly Elevate Sync Reports: Not directly queryable via SOQL. ' +
        'Review Einstein Analytics scheduled jobs and avoid high-frequency syncs.'));
}else if (lowerName.contains('hourlyelevateasyncreportruns')) {
    suggestions.add(new SuggestionWrapper('Hourly Elevate Async Reports: Usage not accessible through SOQL. ' +
        'Use Analytics Studio monitoring tools to manage async jobs.'));
}else if (lowerName.contains('concurrentsyncreportruns')) {
    suggestions.add(new SuggestionWrapper('Concurrent Sync Reports: Real-time usage not available in SOQL. ' +
        'Stagger scheduled reports to avoid peak-hour collisions.'));
}else if (lowerName.contains('concurrentasyncgetreportinstances')) {
    suggestions.add(new SuggestionWrapper('Concurrent Async Report Instances: Cannot be queried directly. ' +
        'Check Setup > Reports & Dashboards or use Event Monitoring to monitor async jobs.'));
}else if (lowerName.contains('publishcallbackusageinapex')) {
    suggestions.add(new SuggestionWrapper(
        'Publish Callback Usage in Apex is not directly queryable. ' +
        'Review your Platform Event triggers and avoid excessive chained publish calls in Apex.'
    ));
}else if (lowerName.contains('dailyasyncapexexecutions')) {
    Integer jobsToday = [SELECT COUNT() FROM AsyncApexJob WHERE CreatedDate = TODAY];
    suggestions.add(new SuggestionWrapper(
        'Async Apex Jobs today: ' + jobsToday +
        '. Review scheduled jobs, batch classes, and queueable chains. Avoid unnecessary chaining or recursive jobs.'
    ));
}else if (lowerName.contains('dailyasyncapextests')) {
    Integer asyncTestJobs = [SELECT COUNT() FROM AsyncApexJob WHERE CreatedDate = TODAY AND JobType = 'Test'];
    suggestions.add(new SuggestionWrapper(
        'Async Test Executions today: ' + asyncTestJobs +
        '. Reduce the number of parallel test runs or use synchronous tests in non-peak hours.'
    ));
}else if (lowerName.contains('hourlytimebasedworkflow')) {
    Datetime oneHourAgo = System.now().addHours(-1);
    Integer workflowItems = [SELECT COUNT() FROM ProcessInstanceStep WHERE CreatedDate >= :oneHourAgo];
    suggestions.add(new SuggestionWrapper(
        'Time-based workflow items created in the past hour: ' + workflowItems +
        '. Consider optimizing your time-based workflows or migrating them to scheduled flows.'
    ));
}else if (lowerName.contains('dailymetadataretrieveswithdependencies')) {
    Datetime today = System.today();
    Integer retrieveCount = [
        SELECT COUNT()
        FROM AsyncApexJob
        WHERE JobType = 'MetadataRetrieve'
        AND CreatedDate >= :today
    ];
    suggestions.add(new SuggestionWrapper(
        'Metadata retrieve jobs run today: ' + retrieveCount +
        '. Consider retrieving only required metadata instead of all dependencies.'
    ));
}else if (lowerName.contains('package2versioncreateswithoutvalidation')) {
  
    suggestions.add(new SuggestionWrapper(
        'Package2Version records created today without being released. Avoid creating package versions without proper validation or release.'
    ));
}else if (lowerName.contains('package2versioncreates')) {
    suggestions.add(new SuggestionWrapper(
        'Package2Version records created today. Minimize unnecessary package version creation. Use unlocked packages and version control carefully.'
    ));
}else if (lowerName.contains('dailyanalyticsdataflowjobexecutions')) {
    suggestions.add(new SuggestionWrapper(
        'Daily Analytics Dataflow Job Executions. ' +
        'Monitor through Analytics settings or REST API as this is not directly queryable.'
    ));
}else if (lowerName.contains('dailyanalyticsuploadedfilessizemb')) {
     suggestions.add(new SuggestionWrapper(
            'Total analytics files uploaded today Consider compressing files or using external storage for large datasets.'
        ));
}else if (lowerName.contains('analyticsexternaldatasizemb')) {
    suggestions.add(new SuggestionWrapper(
        'External data size in Analytics. Monitor through Analytics settings. ' +
        'Archive old datasets or use data partitioning to reduce storage needs.'
    ));
}else if (lowerName.contains('dailyeinsteindiscoverypredictionsbycdc')) {
    suggestions.add(new SuggestionWrapper(
        'Daily Einstein Discovery predictions via CDC. ' +
        'Review prediction job schedules and optimize model usage.'
    ));
}else if (lowerName.contains('monthlyeinsteindiscoverystorycreation')) {
        Date firstOfMonth = System.today().toStartOfMonth();
        Integer storiesThisMonth = Database.countQuery(
            'SELECT COUNT() FROM Einstein_Story__c WHERE CreatedDate >= :firstOfMonth'
        );
        suggestions.add(new SuggestionWrapper(
            'Einstein Discovery stories created this month: ' + storiesThisMonth +
            '. Consider reusing existing stories rather than creating new ones.'
        ));
}else if (lowerName.contains('dailyeinsteindiscoverystorycreation')) {
        Integer storiesToday = Database.countQuery(
            'SELECT COUNT() FROM Einstein_Story__c WHERE CreatedDate = TODAY'
        );
        suggestions.add(new SuggestionWrapper(
            'Einstein Discovery stories created today: ' + storiesToday +
            '. Limit story creation to essential use cases.'
        ));
}else if (lowerName.contains('dailyeinsteindatainsightsstorycreation')) {
        Integer insightsToday = Database.countQuery(
            'SELECT COUNT() FROM DataInsightsStory__c WHERE CreatedDate = TODAY'
        );
        suggestions.add(new SuggestionWrapper(
            'Einstein Data Insights stories created today: ' + insightsToday +
            '. Consolidate insights where possible.'
        ));
} else if (lowerName.contains('concurrenteinsteindatainsightsstorycreation')) {
    suggestions.add(new SuggestionWrapper(
        'Concurrent Einstein Data Insights story creation. ' +
        'Stagger story generation jobs to avoid hitting concurrent limits.'
    ));
}else if (lowerName.contains('concurrenteinsteindiscoverystorycreation')) {
    suggestions.add(new SuggestionWrapper(
        'Concurrent Einstein Discovery story creation. ' +
        'Implement queueing mechanism for story generation requests.'
    ));
}else if (lowerName.contains('dailyeinsteindiscoveryoptimizationjobruns')) {
        Integer optimizationJobs = Database.countQuery(
            'SELECT COUNT() FROM Einstein_Optimization_Job__c WHERE CreatedDate = TODAY'
        );
        suggestions.add(new SuggestionWrapper(
            'Einstein Discovery optimization jobs run today: ' + optimizationJobs +
            '. Schedule optimization jobs during off-peak hours.'
        ));
} else if (lowerName.contains('dailybulkv2queryjobs')) {
    suggestions.add(new SuggestionWrapper(
        'Bulk API v2 query jobs used today. Monitor scheduled jobs and prefer filtering queries.'
    ));
} else if (lowerName.contains('permissionsets')) {
        Integer totalPermSets = [SELECT COUNT() FROM PermissionSet];
suggestions.add(new SuggestionWrapper(
    'Total Permission Sets: ' + totalPermSets +
    '. Review and remove unused permission sets to keep your org clean and easy to manage.'
));

} else if (lowerName.contains('hourlyodatacallout')) {
    suggestions.add(new SuggestionWrapper(
        'Hourly OData callouts. Used by Salesforce Connect. Reduce data refresh frequency.'
    ));
} else if (lowerName.contains('hourlylongtermidmapping')) {
    suggestions.add(new SuggestionWrapper(
        'Long-term ID mapping limit used for referencing deleted records. Avoid referencing old records.'
    ));
} else if (lowerName.contains('hourlyshorttermidmapping')) {
    suggestions.add(new SuggestionWrapper(
        'Short-term ID mapping used for temp tracking. Avoid unnecessary syncs or external ID lookups.'
    ));
} else {
    suggestions.add(new SuggestionWrapper('No specific advice. Review object and process usage to optimize.'));
}
    } catch (Exception ex) {
         suggestions.clear();
        suggestions.add(new SuggestionWrapper('⚠️ Error while generating suggestions: ' + ex.getMessage()));
    }
        return suggestions;
    }
}