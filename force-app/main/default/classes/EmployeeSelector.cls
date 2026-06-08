public with sharing class EmployeeSelector {

    public class LeaveException extends Exception {}

    public static List<Contact> getAllEmployees() {
        return [
            SELECT Id, FirstName, LastName, Email, Department, Title, Phone
            FROM Contact
            WHERE RecordType.DeveloperName = 'Employee'
            ORDER BY LastName
        ];
    }

    public static Contact getEmployeeById(Id employeeId) {
        List<Contact> results = [
            SELECT Id, FirstName, LastName, Email, Department, Title, Phone,
                (SELECT Id, Name, Status__c, Start_Date__c, End_Date__c,
                        Reason__c, Days_Requested__c
                 FROM Leave_Requests__r
                 ORDER BY Start_Date__c DESC
                 LIMIT 5)
            FROM Contact
            WHERE Id = :employeeId
              AND RecordType.DeveloperName = 'Employee'
        ];
        if (results.isEmpty()) {
            throw new LeaveException('Employee not found: ' + employeeId);
        }
        return results[0];
    }
}
