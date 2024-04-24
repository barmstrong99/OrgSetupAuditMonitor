/**
 * Created by Brian Armstrong on 2020-05-06.
 */

@IsTest
private class OrgSetupAuditMonitorTest {

    static final string debugPrefix = OrgUtilities.AsciiArtString(OrgUtilities.AsciiArtEnum.FISH_RIGHT);

    @IsTest
    static void TestConstructor() {
        OrgSetupAuditMonitor setupAudit = new OrgSetupAuditMonitor();

        System.assertNotEquals(null, setupAudit, 'OrgSetupAuditMonitor constructor failed.');

        setupAudit = null;
    }


    static testmethod void TestScheduling() {
        System.debug(System.LoggingLevel.DEBUG, debugPrefix + ' TestScheduling - entry');

        //need start test and end test to ensure synchronous event
        Test.startTest();

        String scheduleJobId;

        // Schedule the class to run hourly.
        scheduleJobId = OrgSetupAuditMonitor.ScheduleClassHourly();

        System.assertNotEquals('', scheduleJobId, 'Schedule job failed.');

        // Schedule the class to run in the future.
        scheduleJobId = OrgSetupAuditMonitor.ScheduleClassForTesting(5);

        System.assertNotEquals('', scheduleJobId, 'Schedule job failed.');
        
        //create instance of our schedule class and schedule it
        OrgSetupAuditMonitor scheduleClass = new OrgSetupAuditMonitor();

        String timeToSchedule = '0 0 22 * * ?'; //everyday at 11pm
        String jobId = System.schedule('Test OrgSetupAuditMonitor Check', timeToSchedule, scheduleClass);

        // Get the information from the CronTrigger API object.
        CronTrigger ct = [SELECT Id, CronExpression, TimesTriggered, NextFireTime FROM CronTrigger WHERE id = :jobId];

        // Verify the job has not run
        System.assertEquals(0, ct.TimesTriggered);

        // Verify next fire time is correct.
        Date today = System.today();
        Time todayTime = time.newInstance(22, 0, 0, 0);
        DateTime dateTimetoSchedule = datetime.newInstance(today, todayTime);
        if (dateTimetoSchedule.getTime() < DateTime.now().getTime()) {
            dateTimetoSchedule = dateTimetoSchedule.addDays(1);
        }
        System.assertEquals(dateTimetoSchedule.format(), ct.NextFireTime.format());

        System.debug('ct: ' + ct);
        System.debug('nextfiretime: ' + ct.NextFireTime.format());
        System.debug('datetime: ' + dateTimetoSchedule.format());

        Test.stopTest();

        System.debug(System.LoggingLevel.DEBUG, debugPrefix + ' TestScheduling - exit');
    }


    @IsTest
    static void TestParseSetupAuditLog() {

        System.debug(System.LoggingLevel.DEBUG, debugPrefix + ' TestParseSetupAuditLog - entry');

        OrgSetupAuditMonitor setupAudit = new OrgSetupAuditMonitor();
        setupAudit.useHTML = True;
        //setupAudit.lookbackHoursPeriod = -5;
        setupAudit.lookbackMinutesPeriod = -300;
        setupAudit.ParseSetupAuditLogs();
        setupAudit = null;

        setupAudit = new OrgSetupAuditMonitor();
        setupAudit.useHTML = True;
        setupAudit.lookbackMinutesPeriod = 200;
        setupAudit.ParseSetupAuditLogs();
        setupAudit = null;

        setupAudit = new OrgSetupAuditMonitor();
        setupAudit.useHTML = false;
        setupAudit.ParseSetupAuditLogs();
        setupAudit = null;

        System.debug(System.LoggingLevel.DEBUG, debugPrefix + ' TestParseSetupAuditLog - exit');
    }


    @IsTest
    static void TestFeatures() {

        System.debug(System.LoggingLevel.DEBUG, debugPrefix + ' TestParseSetupAuditLog - entry');

        OrgSetupAuditMonitor setupAudit = new OrgSetupAuditMonitor();
        setupAudit.useHTML = True;
        setupAudit.usersToMonitor.add('some.user@company.com');
        setupAudit.ParseSetupAuditLogs();
        setupAudit = null;

        setupAudit = new OrgSetupAuditMonitor();
        setupAudit.useHTML = True;
        setupAudit.usersToMonitor.add('test.user@company.com');
        setupAudit.ParseSetupAuditLogs();
        setupAudit = null;

        setupAudit = new OrgSetupAuditMonitor();
        setupAudit.useHTML = True;
        setupAudit.ignoreUsers.add('some.user@company.com');
        setupAudit.ParseSetupAuditLogs();
        setupAudit = null;

        setupAudit = new OrgSetupAuditMonitor();
        setupAudit.useHTML = false;
        setupAudit.usersToMonitor.add('some.user@company.com');
        setupAudit.ParseSetupAuditLogs();
        setupAudit = null;

        System.debug(System.LoggingLevel.DEBUG, debugPrefix + ' TestParseSetupAuditLog - exit');
    }


    // Setup any test data needed by the test methods.
    @testSetup static void SetupTestData() {
        // Create any data needed.
    }


}