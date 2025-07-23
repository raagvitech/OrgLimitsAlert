public with sharing class LimitsForATransactionController {
    @AuraEnabled(cacheable=true)
    public static List<OrgLimitWrapper> getOrgLimits() {
        Map<String, System.OrgLimit> systemLimits = System.OrgLimits.getMap();
        List<OrgLimitWrapper> limits = new List<OrgLimitWrapper>();
        
        for (String key : systemLimits.keySet()) {
            System.OrgLimit orgLimit = systemLimits.get(key);
            limits.add(new OrgLimitWrapper(
                key,
            orgLimit.getValue(),   // value = used
            orgLimit.getLimit()    // limit = max
                ));
        }
        return limits;
    }
    
    public class OrgLimitWrapper {
        @AuraEnabled public String name;
        @AuraEnabled public Integer used;
        @AuraEnabled public Integer max;
        
        public OrgLimitWrapper(String name, Integer used, Integer max) {
            this.name = name;
            this.used = used;
            this.max = max;
        }
    }
}