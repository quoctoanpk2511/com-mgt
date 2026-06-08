public with sharing class LeaveRequestService {

    public class LeaveException extends Exception {}

    private static final Set<String> VALID_STATUSES = new Set<String>{ 'Approved', 'Rejected' };

    public static Leave_Request__c createLeaveRequest(
        Id employeeId,
        Date startDate,
        Date endDate,
        String reason
    ) {
        List<Leave_Request__c> overlaps = [
            SELECT Id
            FROM Leave_Request__c
            WHERE Employee__c = :employeeId
                AND Status__c != 'Rejected'
                AND Start_Date__c <= :endDate
                AND End_Date__c >= :startDate
            LIMIT 1
        ];
        if (!overlaps.isEmpty()) {
            throw new LeaveException('Overlapping leave request already exists.');
        }

        Leave_Request__c lr = new Leave_Request__c(
            Employee__c  = employeeId,
            Start_Date__c = startDate,
            End_Date__c   = endDate,
            Reason__c     = reason,
            Status__c     = 'Pending'
        );
        insert lr;
        return lr;
    }

    public static Leave_Request__c updateLeaveStatus(
        Id leaveRequestId,
        String newStatus,
        Id approverId
    ) {
        if (!VALID_STATUSES.contains(newStatus)) {
            throw new LeaveException('Invalid status: ' + newStatus + '. Must be Approved or Rejected.');
        }

        update new Leave_Request__c(
            Id            = leaveRequestId,
            Status__c     = newStatus,
            Approved_By__c = approverId
        );

        return [
            SELECT Id, Name, Status__c, Approved_By__c, Employee__c,
                    Start_Date__c, End_Date__c, Reason__c, Days_Requested__c
            FROM Leave_Request__c
            WHERE Id = :leaveRequestId
        ];
    }
}
