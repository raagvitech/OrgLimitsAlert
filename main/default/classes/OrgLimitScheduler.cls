global class OrgLimitScheduler implements Schedulable {

    global void execute(SchedulableContext sc) {
        LimitsForATransactionController.getOrgLimits();
    }

    public static void scheduleJobsDynamically() {
        List<Org_Limit_Schedule_Config__mdt> configs = [
            SELECT Cron_Expression__c, Job_Identifier__c FROM Org_Limit_Schedule_Config__mdt
        ];

        for (Org_Limit_Schedule_Config__mdt config : configs) {
            System.schedule(config.Job_Identifier__c, config.Cron_Expression__c, new OrgLimitScheduler());
        }
    }
}
