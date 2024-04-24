/**
* This class is used to monitor setup changes on an organization.
*   This class implements the Schedulable interface and implements its methods.
* @author brian.armstrong
* @governance 1 SOQL calls + No DML calls
**/

global class OrgSetupAuditMonitor implements Schedulable {

    // Names of users for known user Ids.
    private Map<Id, String> knownUserIds = new Map<Id, String>{
        '00540000000z9R3AAI' => 'salesforce.com, inc.',

        '00540000001A5gMAAS' => 'Automated Process',
        '0053300000455K7AAI' => 'Salesforce CPQ',
        '00533000004AYUuAAO' => 'Advanced Approvals',
        '005f3000004ClQZAA0' => 'Lane Four',
        '005f3000005KGJLAA4' => 'Traction Hierarchies',
        '005f3000004QVy4AAG' => 'Prodly AppOps',
        '0054y000005vMdsAAE' => 'FinancialForce Foundations',
        '0054y0000060p5LAAQ' => 'Reporting (FF)',
        '0054y000005vOKOAA2' => 'PS Enterprise',
        '005f3000005JhXcAAK' => 'Opportunity Team Edit Override',
        '0054y000005vS4PAAU' => '6sense Sales Intelligence',
        '005f30000036MLFAA2' => 'b2bmaIntegration',
        '005f3000005JXQ2AAO' => 'D&B Optimizer',
        '0057g000007ZFPMAA4' => 'D&B Connect',
        
        // Old users associated with the applications.
        '005f3000004KGrEAAW' => 'Pardot',
        '005f3000004CnkvAAC' => 'Gainsight CSM',
        '005f3000005BpHZAA0' => 'Trail Tracker',
        '005f3000004T1jPAAS' => 'Salesforce Agile Accelerator'
    };

    // Org Name of the audit log we are monitoring.
    private String orgName = '';

    // look back time period
    public integer lookbackMinutesPeriod = 90;

    // The format for the date and time fields.
    private static final String DATETIME_FORMAT = 'yyyy-MM-dd hh:mm:ss a z';

    // Limit the number of rows queried.
    private Integer limitRows = 15000;

    // Send the email in HTML format.
    public Boolean useHTML = True;

    // SalesForce Organizations
    private static final String PRODUCTION_ORGANIZATION = 'Production';
    private static final List <String> STATUS_EMAIL_ADDRESSES = new List<String>{'some.user@company.com'};  // Used for sending status update emails.

    // Email subject.
    private static final String EMAIL_SUBJECT = 'Setup change(s) have occurred on Org';
    private static final String EMAIL_SUBJECT_SUMMARY = 'Summary of setup change(s) that have occurred on Org';


    class OrgMonitorOptions {
        public Boolean active;
        public String filterWhere;
        // The DateTime used in the filter CreatedDate.
        public DateTime filterCreatedDate;

        // List of sections to ignore from the audit log events.
        public Set<String> ignoreSections;
        public Boolean ignoreBlankSection;

        // List of actions to ignore from the audit log events.
        public Set<String> ignoreActions;
        public Boolean ignoreBlankAction;

        public Boolean ignoreNullCreatedByUserName;

        // List of users to ignore changes from.
        public List<String> ignoreUsers;

        public boolean useHTML; 
        // Email subject.
        public String emailSubject;
        // Email body lines.
        public List<String> emailBodyLines;
        // Show Id
        public boolean showId;
        public boolean showGMTDate;
        public boolean showVerboseBody;

        // Use the Email Event logic. 
        public boolean useEmailEvent;
        public boolean showDebug;
        public boolean showBranding;

        public boolean emailSlack;
   }

    private OrgMonitorOptions adminMonitorOptions = new OrgMonitorOptions();
    private OrgMonitorOptions summaryMonitorOptions = new OrgMonitorOptions();
    private List<OrgMonitorOptions> monitorOptions = new List<OrgMonitorOptions>();

    // List of users to monitor for changes.
    public List<String> usersToMonitor = new List<String>();

    // List of users to ignore changes from.
    public List<String> ignoreUsers = new List<String>();

    global class JobRunStatsClass {
        // Rotating history of setup audit trials processed.
        private Map<Id, Datetime> historySetupAuditTrials = null;

        // The last time the class was run.
        private DateTime lastRunDT;
        // The DateTime when the class is run.
        private DateTime runDT;
    }
    private JobRunStatsClass jobRunStats = null;

     // Debug settings.
    private static final string debugPrefix = OrgUtilities.AsciiArtString(OrgUtilities.AsciiArtEnum.FISH_RIGHT);

    // Code settings class.
    private class CodeSettingClass extends OrgCodeSetting {

        public Integer overrideMinutePeriod = null;
        public Boolean showId = null;
        public Boolean debugStatusEmail = false; 

        public Boolean sendAdminEmail = null;
        public Boolean sendSummaryEmail = null;

        public String slackEmailAddress = null;

        public CodeSettingClass(string className) {
            LoadCodeSetting(className);

            // The Code Settings is IsLoaded and IsActive.
            if (this.IsLoaded && this.IsActive) {

                if (Test.isRunningTest()) {
                    RunningTest(Test.isRunningTest());
                    showId = true;
                    debugStatusEmail = true;

                    sendAdminEmail = true;
                    sendSummaryEmail = true;
                }

                // Show Id of the record.
                final string DF_SHOWID = 'showid';
                if (this.Debug && this.IsDebugFlag(DF_SHOWID)){
                    Boolean b = Boolean.valueOf(DebugFlagValue(DF_SHOWID));
                    if (null != b) {
                        showId = b;
                    }
                }

                // Override Minute Period
                final string F_OMP = 'OMP';
                if (this.Debug && this.IsDebugFlag(F_OMP) ){
                    Integer i = Integer.valueOf(DebugFlagValue(F_OMP));
                    if (null != i) {
                        overrideMinutePeriod = i;
                    }
                } //else if (this.IsGeneralFlag(F_OMP) ){
                  //  Integer i = Integer.valueOf(GeneralFlagValue(F_OMP));
                  //  if (null != i) {
                  //      overrideMinutePeriod = i;
                  //  }
                  //}

                // Debug Status Email
                final string DF_DEBUGSTATUSEMAIL = 'DSE';
                if (this.Debug && this.IsDebugFlag(DF_DEBUGSTATUSEMAIL)){
                    Boolean b = Boolean.valueOf(DebugFlagValue(DF_DEBUGSTATUSEMAIL));
                    if (null != b) {
                        debugStatusEmail = b;
                    }
                }

                // Admin Email.
                final string GF_ADMINEMAIL = 'AE';
                if (this.IsGeneralFlag(GF_ADMINEMAIL)){
                    Boolean b = Boolean.valueOf(GeneralFlagValue(GF_ADMINEMAIL));
                    if (null != b) {
                        sendAdminEmail = b;
                    }
                }

                // Summary Email.
                final string GF_SUMMARYEMAIL = 'SE'; 
                if (this.IsGeneralFlag(GF_SUMMARYEMAIL)){
                    Boolean b = Boolean.valueOf(GeneralFlagValue(GF_SUMMARYEMAIL));
                    if (null != b) {
                        sendSummaryEmail = b;
                    }
                }

                // Slack Email Address. 
                final string GF_SLACKEMAILADDRESS = 'SLACK';
                if (this.IsGeneralFlag(GF_SLACKEMAILADDRESS)) {
                    string s = String.valueOf(GeneralFlagValue(GF_SLACKEMAILADDRESS));
                    if (String.IsNotBlank(s)) {
                        slackEmailAddress = s;
                    }
                }

            }

        }

        public override String toString() {
            return '{OrgCodeSetting:{'+ this.ToStringShort() + '}, ' +
                    'overrideMinutePeriod=' + overrideMinutePeriod + ', ' +
                    'showId=' + showId + ', ' +
                    'debugStatusEmail=' + debugStatusEmail + ', ' +
                    'sendAdminEmail=' + sendAdminEmail + ', ' +
                    'sendSummaryEmail=' + sendSummaryEmail + '' +
                    '}';
        }

        // Send an event that will create an email with the status.
        public void EmailEventStatus(String toAddress, String classMethod, List<String> messages)
        {
            string subject = classMethod;
            string body = OrgUtilities.getUserInfoStringHTML() +
                    '<p><b>class.method:</b> ' + classMethod + ' </p>' +
                    '<p><b>messages (Size: ' + messages.size() + '):</b> <br/>' + String.join(messages, '<br/>') + '</p>' +
                    '<p><b>Limits:</b></p>' + OrgUtilities.getLimitsStringHTML();

            try {
                Org_Email_Event__e eventInfo = new Org_Email_Event__e();
                eventInfo.To_Addresses__c = (String.isNotBlank(toAddress) ? toAddress : STATUS_EMAIL_ADDRESSES[0]);
                eventInfo.Subject__c = subject;
                eventInfo.Body__c = body;
                eventInfo.HTML_Body__c = true;
                Database.SaveResult sr = EventBus.publish(eventInfo);
            }
            catch(Exception e) {
            }
        }

        // Send an event that will create an email with the status.
        public void DebugEmailEventStatus(String classMethod, List<String> messages)
        {
            EmailEventStatus((null != DebugEmailAddress ? DebugEmailAddress : STATUS_EMAIL_ADDRESSES[0]), classMethod, messages);
        }

        // Send an event that will create an email with the status.
        public void OverrideEmailEventStatus(String classMethod, List<String> messages)
        {
            EmailEventStatus((null != OverrideEmailAddress ? OverrideEmailAddress : STATUS_EMAIL_ADDRESSES[0]), classMethod, messages);
        }

    }
    private CodeSettingClass codeSettings = null;


    /**
    * Constructor method for class.  We have nothing to instantiate here, we do it on a per batch basis.
    **/
    global OrgSetupAuditMonitor ()
    {
        //System.debug(System.LoggingLevel.DEBUG, debugPrefix + ' OrgSetupAuditMonitor() - constructor');

        if (null == jobRunStats) {
            jobRunStats = new jobRunStatsClass();
            jobRunStats.historySetupAuditTrials = new Map<Id, Datetime>();
            jobRunStats.lastRunDT = System.now();
        }

    }

    /**
     * Constructor method for class.  We have nothing to instantiate here, we do it on a per batch basis.
     **/
    global OrgSetupAuditMonitor (JobRunStatsClass initJobRunStats)
    {
        //System.debug(System.LoggingLevel.DEBUG, debugPrefix + ' OrgSetupAuditMonitor() - constructor');

        jobRunStats = initJobRunStats;
    }

    
    /**
     * Build a Cron Expression in the future to run once.
     */
    private static String BuildCronExpression(integer minutesFromNow){

        DateTime dt = System.now().addMinutes(minutesFromNow);

        String cronExpression = '0 ' + dt.minute() + ' ' + dt.hour() + ' ' + dt.day() + ' ' + dt.month() + ' ? ' + dt.year();
        //System.debug('cronExpression: ' + cronExpression);

        return cronExpression;
    }

    /**
    * Schedule the Setup Audit Trail Monitor class.
    *
    * @param minutesFromNow
    *
    * @return JobId - id of scheduled job.
    */
    global static string ScheduleClassForTesting(Integer minutesFromNow) {
        OrgSetupAuditMonitor monitor = new OrgSetupAuditMonitor();

        // Schedule the batchable class.
        String cronExpression = BuildCronExpression(minutesFromNow);
        String jobName = 'Setup Audit Trail Monitor - Run Once' + (Test.isRunningTest() ? ' - Test' : '') + ' - ' +  System.now().getTime();
        String jobId = System.schedule(JobName, cronExpression, monitor);
        System.Debug('jobName: ' + jobName + ', cronExpression: ' + cronExpression + ', jobId: ' + jobId);

        return jobId;
    }


    /**
    * Schedule the Setup Audit Trail class to run hourly.
    *
    * @return JobId - id of scheduled job.
    */
    global static string ScheduleClassHourly() {

        OrgSetupAuditMonitor monitor = new OrgSetupAuditMonitor();

        // Every hour at the 0 minute mark.
        String cronExpression = '0 0 * * * ?';
        String jobName = 'Setup Audit Trail Monitor - Hourly' + (Test.isRunningTest() ? ' - Test' : '');
        String jobId = System.schedule(jobName, cronExpression, monitor);
        System.Debug('jobName: ' + jobName + ', cronExpression: ' + cronExpression + ', jobId: ' + jobId);

        return jobId;
    }


    /**
     * Execute method is required by the Schedulable interface. It determines what to do when scheduled.
     * @return void : void.
     **/
    global void execute(SchedulableContext sc)
    {
        Id triggerId = sc.getTriggerId();

        //OrgSetupAuditMonitor monitor = new OrgSetupAuditMonitor(historySetupAuditTrials);
        OrgSetupAuditMonitor monitor = new OrgSetupAuditMonitor(jobRunStats);
        monitor.ParseSetupAuditLogs();
    }

    /**
    Sends an email to the Salesforce users.
    @param subject - The subject of the email.
    @param body - List of Strings to create the body of the email.
    **/
    private void SendEmail(String subject, String body, OrgMonitorOptions monitorOption)
    {
        if (monitorOption.useEmailEvent)
            SendEmailEvent(subject, body, monitorOption);
        else
            SendEmailMessage(subject, body, monitorOption);
    }


    /**
    Sends an email to the Salesforce users.
    @param subject - The subject of the email.
    @param body - List of Strings to create the body of the email.
    **/
    private void SendEmailMessage(String subject, String body, OrgMonitorOptions monitorOption)
    {
        // Construct the Single Email Message
        Messaging.SingleEmailMessage message = new Messaging.SingleEmailMessage();

        List<String> toAddresses = null;
        if (codeSettings.IsLoaded && codeSettings.IsActive) {
            if (codeSettings.Debug && codeSettings.DebugEmail) {
                //message.setToAddresses(null != codeSettings.DebugEmailAddresses ? codeSettings.DebugEmailAddresses : STATUS_EMAIL_ADDRESSES);
                toAddresses = (null != codeSettings.DebugEmailAddresses ? codeSettings.DebugEmailAddresses : STATUS_EMAIL_ADDRESSES);
            } else {
                //message.setToAddresses(null != codeSettings.OverrideEmailAddresses ? codeSettings.OverrideEmailAddresses : STATUS_EMAIL_ADDRESSES); 
                toAddresses = (null != codeSettings.OverrideEmailAddresses ? codeSettings.OverrideEmailAddresses : STATUS_EMAIL_ADDRESSES);
            }
        } else {
            //message.setToAddresses(STATUS_EMAIL_ADDRESSES); 
            toAddresses = STATUS_EMAIL_ADDRESSES;
        }
        if (null != toAddresses) {
            message.setToAddresses(toAddresses); 
        }

        if (monitorOption.emailSlack) {
            List<String> ccAddresses = null;
            if (codeSettings.IsLoaded && codeSettings.IsActive) {
                if(String.IsNotBlank(codeSettings.slackEmailAddress)) {
                    ccAddresses = new List<String>{codeSettings.slackEmailAddress};
                }
            }
            if (null != ccAddresses) {
                message.setCCAddresses(ccAddresses);
            }
        }

        message.subject = subject;
        if (True == monitorOption.useHTML) {
            message.htmlBody = body;
        } else {
            message.plainTextBody = body;
        }
        message.saveAsActivity = false;
        message.useSignature = false;

        try {
            // Do not check for errors as nothing to do in that case
            Messaging.sendEmail(new Messaging.SingleEmailMessage[] {message});
        } 
        catch(System.CalloutException e) {
            System.debug('Error: ' + e);
        }
    }

    /**
    Sends an email to the Salesforce users.
    @param subject - The subject of the email.
    @param body - List of Strings to create the body of the email.
    **/
    private void SendEmailEvent(String subject, String body, OrgMonitorOptions monitorOption)
    {
        try {

            String toAddresses; 
            if (codeSettings.IsLoaded && codeSettings.IsActive) {
                if (codeSettings.Debug && codeSettings.DebugEmail) {
                    toAddresses = (null != codeSettings.DebugEmailAddresses ? codeSettings.DebugEmailAddresses[0] : STATUS_EMAIL_ADDRESSES[0]);
                } else {
                    toAddresses = (null != codeSettings.OverrideEmailAddresses ? codeSettings.OverrideEmailAddresses[0] : STATUS_EMAIL_ADDRESSES[0]); 
                }
            } else {
                toAddresses = (STATUS_EMAIL_ADDRESSES[0]); 
            }

            List<Org_Email_Event__e> emailEvents = new List<Org_Email_Event__e> ();
            Org_Email_Event__e emailEvent = new Org_Email_Event__e();

            //emailEvent.From_Addresses__c = orgWideEmailId;  // Organization Wide Addresses.
            emailEvent.To_Addresses__c = toAddresses;
            emailEvent.Subject__c = subject;
            emailEvent.Body__c = body;
            emailEvent.HTML_Body__c = monitorOption.useHTML;
            emailEvent.Debug__c = null;
            emailEvent.Branding__c = monitorOption.showBranding;

            //EventBus.publish(emailEvent);
            emailEvents.add(emailEvent);
            EventBus.publish(emailEvents);
        }
        catch(Exception e) {
            System.debug('Exception: ' + e.getMessage() + ', Stack Trace: ' + e.getStackTraceString());
        }

    }

    private void SetupMonitorOptionDefaults() {
        orgName = (OrgUtilities.isSandbox() ? OrgUtilities.getSandboxName() : PRODUCTION_ORGANIZATION);

        adminMonitorOptions = new OrgMonitorOptions();
        adminMonitorOptions.active = true;
        adminMonitorOptions.filterWhere = '';
        adminMonitorOptions.filterCreatedDate = null;
        adminMonitorOptions.ignoreSections = new Set<String> {'Org Code Settings'};
        adminMonitorOptions.ignoreBlankSection = false;
        adminMonitorOptions.ignoreActions = new Set<String> {};
        adminMonitorOptions.ignoreBlankAction = false;
        adminMonitorOptions.ignoreNullCreatedByUserName = false;
        adminMonitorOptions.emailSubject = EMAIL_SUBJECT;
        adminMonitorOptions.useHTML = useHTML; 
        adminMonitorOptions.emailBodyLines = new List<String>();
        adminMonitorOptions.showId = false;
        adminMonitorOptions.showGMTDate = false;
        adminMonitorOptions.showVerboseBody = true;
        adminMonitorOptions.useEmailEvent = true;
        adminMonitorOptions.showDebug = false;
        adminMonitorOptions.showBranding = true;
        adminMonitorOptions.emailSlack = false;

        summaryMonitorOptions = new OrgMonitorOptions();
        summaryMonitorOptions.active = (OrgUtilities.isProduction() || Test.isRunningTest());
        summaryMonitorOptions.filterWhere = '';
        summaryMonitorOptions.filterCreatedDate = null;
        summaryMonitorOptions.ignoreSections = new Set<String> {'Manage Users', 'Custom Tabs', 'Customer Portal', 'Data Export', 'Org Code Settings'};
        summaryMonitorOptions.ignoreBlankSection = false;
        summaryMonitorOptions.ignoreActions = new Set<String> {};
        summaryMonitorOptions.ignoreBlankAction = false;
        summaryMonitorOptions.ignoreNullCreatedByUserName = true;
        //summaryMonitorOptions.ignoreUsers = ignoreUsers;
        summaryMonitorOptions.emailSubject = EMAIL_SUBJECT_SUMMARY;
        summaryMonitorOptions.useHTML = useHTML; 
        summaryMonitorOptions.emailBodyLines = new List<String>();
        summaryMonitorOptions.showId = false;
        summaryMonitorOptions.showGMTDate = false;
        summaryMonitorOptions.showVerboseBody = false;
        summaryMonitorOptions.useEmailEvent = false;
        summaryMonitorOptions.showBranding = false;
        summaryMonitorOptions.emailSlack = true; 

        monitorOptions.Add(adminMonitorOptions);
        monitorOptions.add(summaryMonitorOptions);
    }

    /**
    * Description: Get the audit log events that occurred in a lookback period and were triggered by specific users
    **/
    public void ParseSetupAuditLogs()
    {
        string classMethod = OrgSetupAuditMonitor.class.getName() + '.ParseSetupAuditLogs';
        System.debug(classMethod);

        // Setup the basic defaults.
        SetupMonitorOptionDefaults();

        codeSettings = new CodeSettingClass(OrgSetupAuditMonitor.class.getName());
        
        if (null != codeSettings.overrideMinutePeriod){
            lookbackMinutesPeriod = codeSettings.overrideMinutePeriod;
        }

        if (null != codeSettings.showId){
            adminMonitorOptions.showId = codeSettings.showId;
            adminMonitorOptions.showGMTDate = codeSettings.showId;
        }

        if (null != codeSettings.sendAdminEmail)
            adminMonitorOptions.active = codeSettings.sendAdminEmail;

        if (null != codeSettings.sendSummaryEmail)
            summaryMonitorOptions.active = codeSettings.sendSummaryEmail;

        // Get the datetime to use to filter out entries.
        jobRunStats.runDT = System.Now();
        //filterCreatedDate = runDT.addHours(-(lookbackHoursPeriod));
        DateTime filterCreatedDate = jobRunStats.runDT.addMinutes(-(lookbackMinutesPeriod));

        // If testing, we want to use all the changes, but limited number of rows.
        if (Test.isRunningTest()) {
            filterCreatedDate = System.Datetime.newInstance(1969, 1, 1);
            limitRows = 300;
        }

        System.debug('runDT: ' + jobRunStats.runDT);
        System.debug('filterCreatedDate: ' + filterCreatedDate);
        System.debug('usersToMonitor.size(): ' + usersToMonitor.size());

        List<SetupAuditTrail> querySetupAuditTrails = null;
        String filterWhere = '';
        if (usersToMonitor.size() >= 1)  {
            // run SOQL on SetupAuditTrail filtering on UserName and CreatedDate
            querySetupAuditTrails = [SELECT Id, CreatedDate, CreatedById, CreatedBy.Name, CreatedBy.UserName, CreatedBy.Email,
                            Action, Section, Display, DelegateUser, CreatedByContext, CreatedByIssuer FROM SetupAuditTrail
                    WHERE CreatedBy.Email IN :usersToMonitor AND CreatedDate >= :filterCreatedDate
                    ORDER BY CreatedDate DESC LIMIT :limitRows];
            filterWhere = 'WHERE CreatedBy.Email IN ' + usersToMonitor + ' AND CreatedDate >= ' + filterCreatedDate +
                    ' ORDER BY CreatedDate DESC LIMIT ' + limitRows;
        } else {
            // run SOQL on SetupAuditTrail filtering on CreatedDate
            querySetupAuditTrails = [SELECT Id, CreatedDate, CreatedById, CreatedBy.Name, CreatedBy.UserName, CreatedBy.Email,
                            Action, Section, Display, DelegateUser, CreatedByContext, CreatedByIssuer FROM SetupAuditTrail
                    WHERE CreatedDate >= :filterCreatedDate
                    ORDER BY CreatedDate DESC LIMIT :limitRows];
            filterWhere = 'WHERE CreatedDate >= ' + filterCreatedDate +
                    ' ORDER BY CreatedDate DESC LIMIT ' + limitRows;
        }
        System.debug('querySetupAuditTrails.size(): ' + querySetupAuditTrails.size());
        System.debug('filterWhere: ' + filterWhere);

        if (codeSettings.Debug && codeSettings.DebugEmail && codeSettings.debugStatusEmail) { 
            codeSettings.DebugEmailEventStatus(classMethod, new List<String> {
                'codeSettings: ' + codeSettings.toString() + '<br/>',
                'lastRunDT: ' + jobRunStats.lastRunDT + ', Local: ' + jobRunStats.lastRunDT.format(DATETIME_FORMAT, userinfo.getTimeZone().toString()),
                'runDT: ' + jobRunStats.runDT + ', Local: ' + jobRunStats.runDT.format(DATETIME_FORMAT, userinfo.getTimeZone().toString()),
                'filterCreatedDate: ' + filterCreatedDate + ', Local: ' + filterCreatedDate.format(DATETIME_FORMAT, userinfo.getTimeZone().toString()),
                'filterWhere: ' + filterWhere,
                 '<b>querySetupAuditTrails.size(): ' + querySetupAuditTrails.size() + '</b><br/>',
                'historySetupAuditTrials (Size: ' + jobRunStats.historySetupAuditTrials.size() + '): ' + jobRunStats.historySetupAuditTrials
            } ); 
        } 

        // No setup audit trail rows found with the criteria.
        if (querySetupAuditTrails.isEmpty()) {
            System.debug('querySetupAuditTrails is Empty');
            return;
        }

        System.debug('historySetupAuditTrials.size(): ' + jobRunStats.historySetupAuditTrials.size());

        // Check if the change is already in the history setup audit trail
        List<SetupAuditTrail> changedSetupAuditTrails = new List<SetupAuditTrail>();
        for (SetupAuditTrail sat : querySetupAuditTrails) {
            if (!jobRunStats.historySetupAuditTrials.containsKey(sat.Id)) {
                jobRunStats.historySetupAuditTrials.put(sat.Id, sat.CreatedDate);
                changedSetupAuditTrails.Add(sat);
            }
        }

        System.debug('changedSetupAuditTrails.size(): ' + changedSetupAuditTrails.size());
        System.debug('historySetupAuditTrials.size(): ' + jobRunStats.historySetupAuditTrials.size());

        // remove out the old setup audit trails older than the filter date.
        Map<Id, Datetime> removedSetupAuditTrials = new Map<Id, Datetime>();
        for (Id satId : jobRunStats.historySetupAuditTrials.keySet()) {
            Datetime dt = jobRunStats.historySetupAuditTrials.get(satId);
            if (dt < filterCreatedDate) {
                jobRunStats.historySetupAuditTrials.remove(satId);
                removedSetupAuditTrials.put(satId, dt);
            }
        }

        System.debug('removedSetupAuditTrials.size(): ' + removedSetupAuditTrials.size());
        System.debug('historySetupAuditTrials.size(): ' + jobRunStats.historySetupAuditTrials.size());

        for (OrgMonitorOptions mo : monitorOptions) {
            mo.filterWhere = filterWhere;
            mo.filterCreatedDate = filterCreatedDate;

            if (!mo.active)
                continue;

            // parse the query to build the body for the email
            //for (SetupAuditTrail sat : querySetupAuditTrails) {
            for (SetupAuditTrail sat : changedSetupAuditTrails) {
                // Ignore some sections in the audit trail.
                if (mo.ignoreSections.contains(sat.section)) {
                    continue;
                }

                // Ignore a blank section. 
                if (mo.ignoreBlankSection && String.isBlank(sat.Section)) {
                    continue;
                }

                // Ignore some actions in the audit trail.
                if (mo.ignoreActions.contains(sat.Action)) {
                    continue;
                }

                // Ignore a blank action.
                if (mo.ignoreBlankAction && String.isBlank(sat.Action)) {
                    continue;
                }

                // if the user name is blank, it is a user outside our org. 
                if (mo.ignoreNullCreatedByUserName && String.isBlank(sat.CreatedBy.Username)) {
                    continue;
                }

                // Ignore changes by some users.
                if (ignoreUsers.contains(sat.CreatedBy.Email)){
                    continue;
                }

                String emailLine;
                if (true == mo.useHTML) {
                    emailLine = HTMLDetailLine(sat, mo);
                } else {
                    emailLine = TextDetailLine(sat, mo);
                }

                //emailBodyList.add(emailLine);
                mo.emailBodyLines.add(emailLine);
            }

            System.debug('mo.emailBodyLines.size(): ' + mo.emailBodyLines.size());
            if (!mo.emailBodyLines.isEmpty()) {
                String subject = orgName + ' - ' + mo.emailSubject;

                string body = '';
                if (true == mo.useHTML) {
                    body = HTMLBody(mo);
                } else {
                    body = TextBody(mo);
                }

                SendEmail(subject, body, mo);
            }

        }

        if (codeSettings.Debug && codeSettings.DebugEmail && codeSettings.debugStatusEmail) { 
            codeSettings.DebugEmailEventStatus(classMethod, new List<String> {
                'runDT: ' + jobRunStats.runDT + ', Local: ' + jobRunStats.runDT.format(DATETIME_FORMAT, userinfo.getTimeZone().toString()) + '<br/>',
                '<b>querySetupAuditTrails.size(): ' + querySetupAuditTrails.size() + '</b>'+ '<br/>',
                'changedSetupAuditTrails (Size: ' + changedSetupAuditTrails.size() + '): ' + changedSetupAuditTrails + '<br/>',
                'historySetupAuditTrials (Size: ' + jobRunStats.historySetupAuditTrials.size() + '): ' + jobRunStats.historySetupAuditTrials + '<br/>',
                'removedSetupAuditTrials (Size: ' + removedSetupAuditTrials.size() + '): ' + removedSetupAuditTrials + '<br/>',
                'adminMonitorOptions.emailBodyLines.size(): ' + adminMonitorOptions.emailBodyLines.size(),
                'summaryMonitorOptions.emailBodyLines.size(): ' + summaryMonitorOptions.emailBodyLines.size()
            } ); 
        } 

        jobRunStats.lastRunDT = jobRunStats.runDT;
        System.debug('lastRunDT: ' + jobRunStats.lastRunDT);

    }


   /**
     * Description: This method returns a header string for the object.
     **/
    private string TextHeaderLine(OrgMonitorOptions monitorOption)
    {
        String line =
                'Date, ' +
                'User, ' + 
                'Display, ' +
                'Action, ' +
                'Section, ' +
                'DelegateUser' + 
                (monitorOption.showId ? ', Id' : '');

        return line;
    }


    /**
     * Description: This method returns a text string representation of the object.
     **/
    private string TextDetailLine(SetupAuditTrail setupAuditTrail, OrgMonitorOptions monitorOption)
    {
        String line =
                '' + setupAuditTrail.CreatedDate +
                ', ' + setupAuditTrail.CreatedBy.UserName +
                ', ' + setupAuditTrail.Display +
                ', ' + setupAuditTrail.Action +
                ', ' + setupAuditTrail.Section +
                ', ' + setupAuditTrail.DelegateUser +
                (monitorOption.showId ? ', ' + setupAuditTrail.Id : '');

        return line;
    }


    /**
    * Description: This method returns a text string representation of the object.
    **/
    private string TextBody(OrgMonitorOptions monitorOption)
    {
        String textBody = TextHeaderLine(monitorOption) + '\n' + String.join(monitorOption.emailBodyLines, '\n') + 'Filter used: ' + monitorOption.filterWhere;

        return textBody;
    }


    /**
     * Description: This method returns an HTML header ling for the object.
     **/
    private string HTMLHeaderLine(OrgMonitorOptions monitorOption)
    {
        String line =
                '<tr>' +
                '<th class="" style="border: 1px solid rgb(204, 204, 204); background: rgb(245, 245, 245); padding: 3px 4px; text-align: center;">CreatedDate</th>' +
                //'<th class="" style="border: 1px solid rgb(204, 204, 204); background: rgb(245, 245, 245); padding: 3px 4px; text-align: center;">Date</th>' +
                //'<th class="" style="border: 1px solid rgb(204, 204, 204); background: rgb(245, 245, 245); padding: 3px 4px; text-align: center;">Name</th>' +
                //'<th class="" style="border: 1px solid rgb(204, 204, 204); background: rgb(245, 245, 245); padding: 3px 4px; text-align: center;">UserName</th>' +
                '<th class="" style="border: 1px solid rgb(204, 204, 204); background: rgb(245, 245, 245); padding: 3px 4px; text-align: center;">User</th>' +
                '<th class="" style="border: 1px solid rgb(204, 204, 204); background: rgb(245, 245, 245); padding: 3px 4px; text-align: center;">Display</th>' +
                '<th class="" style="border: 1px solid rgb(204, 204, 204); background: rgb(245, 245, 245); padding: 3px 4px; text-align: center;">Action</th>' +
                '<th class="" style="border: 1px solid rgb(204, 204, 204); background: rgb(245, 245, 245); padding: 3px 4px; text-align: center;">Section</th>'+
                '<th class="" style="border: 1px solid rgb(204, 204, 204); background: rgb(245, 245, 245); padding: 3px 4px; text-align: center;">DelegateUser</th>' +
                (true == monitorOption.showId ? '<th class="" style="border: 1px solid rgb(204, 204, 204); background: rgb(245, 245, 245); padding: 3px 4px; text-align: center;">Id</th>' : '') +
                (true == monitorOption.showGMTDate ? '<th class="" style="border: 1px solid rgb(204, 204, 204); background: rgb(245, 245, 245); padding: 3px 4px; text-align: center;">GMTCreatedDate</th>' : '') +
                '</tr>';

        return line;
    }


    /**
     * Description: This method returns a text string representation of the object.
     **/
    private string HTMLDetailLine(SetupAuditTrail setupAuditTrail, OrgMonitorOptions monitorOption)
    {
        String createdDateFormatted = setupAuditTrail.CreatedDate.format(DATETIME_FORMAT, userinfo.getTimeZone().toString());

        //String name = (null != setupAuditTrail.CreatedBy.Name ? setupAuditTrail.CreatedBy.Name : ' ');
        String userName = (null != setupAuditTrail.CreatedBy.UserName ? setupAuditTrail.CreatedBy.UserName : ' ');

        if (String.isBlank(userName)) {
            if (knownUserIds.containsKey(setupAuditTrail.CreatedById)) {
                userName = knownUserIds.get(setupAuditTrail.CreatedById) + '<br/>"' + setupAuditTrail.CreatedById + '"';
            } else {
                userName = '"' + setupAuditTrail.CreatedById + '"';
            }
        }
        //String user = name + '<br/>' + userName;
        String user = userName;

        String line =
                '<tr>' +
                '<td class="" style="border: 1px solid rgb(204, 204, 204); padding: 3px 4px;">' + createdDateFormatted + '</td>' +
                //'<td class="" style="border: 1px solid rgb(204, 204, 204); padding: 3px 4px;">' + name + '</td>' +
                //'<td class="" style="border: 1px solid rgb(204, 204, 204); padding: 3px 4px;">' + userName + '</td>' +
                '<td class="" style="border: 1px solid rgb(204, 204, 204); padding: 3px 4px;">' + user + '</td>' +
                '<td class="" style="border: 1px solid rgb(204, 204, 204); padding: 3px 4px;">' + setupAuditTrail.Display + '</td>' +
                '<td class="" style="border: 1px solid rgb(204, 204, 204); padding: 3px 4px;">' + setupAuditTrail.Action + '</td>' +
                '<td class="" style="border: 1px solid rgb(204, 204, 204); padding: 3px 4px;">' + (null != setupAuditTrail.Section ? setupAuditTrail.Section : ' ') + '</td>' +
                '<td class="" style="border: 1px solid rgb(204, 204, 204); padding: 3px 4px;">' + (null != setupAuditTrail.DelegateUser ? setupAuditTrail.DelegateUser : ' ') + '</td>' +
                (true == monitorOption.showId ? '<td class="" style="border: 1px solid rgb(204, 204, 204); padding: 3px 4px;">' + setupAuditTrail.Id + '</td>' : '') +
                (true == monitorOption.showGMTDate ? '<td class="" style="border: 1px solid rgb(204, 204, 204); padding: 3px 4px;">' + setupAuditTrail.CreatedDate.formatGMT(DATETIME_FORMAT) + '</td>' : '') +
                '</tr>';

        return line;
    }


    /**
     * Description: This method returns a text string representation of the object.
     **/
    private string HTMLBody(OrgMonitorOptions monitorOption)
    {
        Long duration = (jobRunStats.runDT.getTime() - monitorOption.filterCreatedDate.getTime()) / 1000 / 60;
        String filterCreatedDateFormatted = monitorOption.filterCreatedDate.format(DATETIME_FORMAT, userinfo.getTimeZone().toString());

        string topHTMLTags = '<html><body>';
        //string tableTopHTMLTags = '<table class="" border="1" style="border-collapse: collapse; margin: 5px 0px 5px 2px; width: auto; color: rgb(23, 43, 77); font-family: -apple-system, BlinkMacSystemFont, &quot;Segoe UI&quot;, Roboto, Oxygen, Ubuntu, &quot;Fira Sans&quot;, &quot;Droid Sans&quot;, &quot;Helvetica Neue&quot;, sans-serif; font-size: 14px; font-style: normal; font-variant-ligatures: normal; font-variant-caps: normal; font-weight: 400; letter-spacing: normal; orphans: 2; text-align: left; text-indent: 0px; text-transform: none; white-space: normal; widows: 2; word-spacing: 0px; -webkit-text-stroke-width: 0px; background-color: rgb(244, 245, 247); text-decoration-style: initial; text-decoration-color: initial;"><tbody>';
        string tableTopHTMLTags = '<table class="" border="1" style="border-collapse: collapse; margin: 5px 0px 5px 2px; width: auto; color: rgb(23, 43, 77); font-family: -apple-system, BlinkMacSystemFont, &quot;Segoe UI&quot;, Roboto, Oxygen, Ubuntu, &quot;Fira Sans&quot;, &quot;Droid Sans&quot;, &quot;Helvetica Neue&quot;, sans-serif; font-size: 14px; font-style: normal; font-variant-ligatures: normal; font-variant-caps: normal; font-weight: 400; letter-spacing: normal; orphans: 2; text-align: left; text-indent: 0px; text-transform: none; white-space: normal; widows: 2; word-spacing: 0px; -webkit-text-stroke-width: 0px; text-decoration-style: initial; text-decoration-color: initial;"><tbody>';
        string tableBottomHTMLTags = '</tbody></table>';
        string bottomHTMLTags = '</body></html>';

        String htmlDetailLines = String.join(monitorOption.emailBodyLines, '');

        string headerLine; 
        String headerInfo;
        String footerInfo;
        string htmlBody;
        Integer numOfChanges = monitorOption.emailBodyLines.size();
        //string changesStr = (numOfChanges == 1 ? 'change' : 'changes');
        //string isAreStr = (numOfChanges == 1 ? 'is' : 'are');
        //string wasWereStr = (numOfChanges == 1 ? 'was' : 'were');
        //string lineOneStr = (numOfChanges == 1 ? 'was a setup change' : 'were setup changes');

        if (1 == numOfChanges) {
            headerLine = '<p>There was ' + numOfChanges + ' setup change on "' + orgName + '" in the last ' + duration + ' minutes:</p>';
        } else {
            headerLine = '<p>There were ' + numOfChanges + ' setup changes on "' + orgName + '" in the last ' + duration + ' minutes:</p>';
        }

        if (monitorOption.showVerboseBody) {
            headerInfo = OrgUtilities.getUserInfoStringHTML() + headerLine;
                //'<p>There ' + lineOneStr + ' on "' + orgName + '" in the last ' + duration + ' minutes. (Change CreatedDate >= ' + filterCreatedDateFormatted + ')</p>' +
                //'<p>There ' + isAreStr + ' ' + numOfChanges + ' setup ' + changesStr + ' listed below:<p>';

            footerInfo = '<p><b>Options:</b><br/>' + 
                    'CreatedDate >= ' + filterCreatedDateFormatted + '<br/>' +
                    'Filter used (in GMT): ' + monitorOption.filterWhere + '<br/>' +
                    'Ignore Actions: ' + monitorOption.ignoreActions + '<br/>' +
                    'Ignore Sections: ' + monitorOption.ignoreSections + '<br/>' +
                    'Ignore Users: ' + monitorOption.ignoreUsers + '<br/>' +
                    'Look back minutes period: ' + lookbackMinutesPeriod + '</p>' +
                    (true==codeSettings.Debug ? '<p>codeSettings: ' + codeSettings + '</p>' : '') +
                    OrgUtilities.getLimitsStringHTML('<b>Limits:</b>');

            htmlBody = topHTMLTags + headerInfo + 
                       tableTopHTMLTags + HTMLHeaderLine(monitorOption) + htmlDetailLines + tableBottomHTMLTags + 
                       footerInfo + bottomHTMLTags;
        } else {
            //headerInfo = '<p>There were ' + monitorOption.emailBodyLines.size() + ' setup changes on "' + orgName + '" in the last ' + duration + ' minutes:</p>';
            //headerInfo = '<p>There ' + wasWereStr + ' ' + numOfChanges + ' setup ' + changesStr + ' on "' + orgName + '" in the last ' + duration + ' minutes:</p>';
            headerInfo = headerLine;
            footerInfo = '<p>' + '</p>';
            htmlBody = topHTMLTags + headerInfo + 
                       tableTopHTMLTags + HTMLHeaderLine(monitorOption) + htmlDetailLines + tableBottomHTMLTags + 
                       footerInfo + bottomHTMLTags;
        }

        return htmlBody;
    }

}