# Company Management — Project Requirements

## 1. Project Overview

| Item | Detail |
|---|---|
| **Project Name** | Company Management |
| **Git Folder** | `com-mgt` |
| **Platform** | Salesforce (API v62.0) |
| **Source Dir** | `force-app/main/default` |
| **Purpose** | Internal employee & leave management system with Slack notifications and public REST API |

### Business Context

Công ty cần một hệ thống quản lý nhân viên và đơn nghỉ phép tập trung trên Salesforce. Manager có thể approve/reject đơn nghỉ, hệ thống tự động notify lên Slack, và bộ phận HR bên ngoài có thể truy vấn thông tin qua REST API công khai.

---

## 2. Environments

| Environment | Org Alias | Org URL | Purpose |
|---|---|---|---|
| Development | `com-mgt-dev` | `https://YOUR_DEV_ORG.my.salesforce.com` | Vibe coding, local testing |
| Staging | `com-mgt-stg` | `https://YOUR_STG_ORG.my.salesforce.com` | UAT, integration test |
| Production | `com-mgt-prod` | `https://YOUR_PROD_ORG.my.salesforce.com` | Live |

> Điền Org URL thực tế sau khi login: `sf org display --target-org com-mgt-dev`

---

## 3. Repository Structure

```
com-mgt/
├── force-app/
│   └── main/
│       └── default/
│           ├── classes/
│           │   ├── EmployeeSelector.cls
│           │   ├── EmployeeSelector.cls-meta.xml
│           │   ├── LeaveRequestService.cls
│           │   ├── LeaveRequestService.cls-meta.xml
│           │   ├── SlackCalloutService.cls
│           │   ├── SlackCalloutService.cls-meta.xml
│           │   ├── CompanyManagementAPI.cls
│           │   ├── CompanyManagementAPI.cls-meta.xml
│           │   ├── LeaveRequestServiceTest.cls
│           │   └── LeaveRequestServiceTest.cls-meta.xml
│           ├── triggers/
│           │   ├── LeaveRequestTrigger.trigger
│           │   └── LeaveRequestTrigger.trigger-meta.xml
│           ├── objects/
│           │   ├── Leave_Request__c/
│           │   │   ├── Leave_Request__c.object-meta.xml
│           │   │   └── fields/
│           │   │       ├── Employee__c.field-meta.xml
│           │   │       ├── Status__c.field-meta.xml
│           │   │       ├── Start_Date__c.field-meta.xml
│           │   │       ├── End_Date__c.field-meta.xml
│           │   │       ├── Reason__c.field-meta.xml
│           │   │       ├── Approved_By__c.field-meta.xml
│           │   │       └── Days_Requested__c.field-meta.xml
│           │   └── Slack_Config__mdt/
│           │       ├── Slack_Config__mdt.object-meta.xml
│           │       └── fields/
│           │           ├── Bot_Token__c.field-meta.xml
│           │           └── Channel_Id__c.field-meta.xml
│           ├── customMetadata/
│           │   └── Slack_Config.Default.md-meta.xml
│           └── remoteSiteSettings/
│               └── Slack_API.remoteSite-meta.xml
├── manifest/
│   └── package.xml
├── scripts/
│   └── test-create-leave.apex
├── CLAUDE.md
├── REQUIREMENTS.md
└── sfdx-project.json
```

---

## 4. Salesforce Setup (One-time)

### 4.1 RecordType cho Contact

Contact được dùng làm Employee. Cần tạo RecordType thủ công trong Setup:

```
Setup → Object Manager → Contact → Record Types → New
  Label:         Employee
  DeveloperName: Employee
  Active:        ✅
```

### 4.2 Connected App (cho Postman OAuth)

```
Setup → App Manager → New Connected App
  Connected App Name: com-mgt-connected_app
  API Name:           com_mgt_connected_app
  Enable OAuth Settings: ✅
  Callback URL:       https://login.salesforce.com/services/oauth2/success
  Selected OAuth Scopes:
    - Access and manage your data (api)
    - Perform requests on your behalf at any time (refresh_token)
```

Sau khi tạo, lấy **Consumer Key** (`client_id`) và **Consumer Secret** (`client_secret`) từ tab API.

> Security Token: lấy tại `Settings → Reset My Security Token`. Password khi dùng OAuth = `YourPassword + SecurityToken` (ghép liền, không có khoảng trắng).

---

## 5. Salesforce Objects

### 5.1 Standard Objects (reused)

| Object | Fields dùng | Notes |
|---|---|---|
| `Contact` | `FirstName`, `LastName`, `Email`, `Department`, `Title`, `Phone` | RecordType: `Employee` |
| `User` | `Id`, `Name` | Lưu manager thực hiện approve/reject |
| `Task` | — | Follow-up task sau khi approve (out of scope v1) |

### 5.2 Custom Object: `Leave_Request__c`

**Label:** Leave Request
**Plural:** Leave Requests
**Sharing Model:** ReadWrite
**Name Field:** AutoNumber — format `LR-{00000}`

| Field Label | API Name | Type | Required | Notes |
|---|---|---|---|---|
| Employee | `Employee__c` | Lookup(Contact) | ✅ | RelationshipName: `Leave_Requests` |
| Start Date | `Start_Date__c` | Date | ✅ | |
| End Date | `End_Date__c` | Date | ✅ | |
| Reason | `Reason__c` | Long Text Area | | 32768 chars |
| Status | `Status__c` | Picklist | ✅ | Values: `Pending` (default), `Approved`, `Rejected` |
| Approved By | `Approved_By__c` | Lookup(User) | | Set khi manager approve/reject |
| Days Requested | `Days_Requested__c` | Formula(Number) | | `End_Date__c - Start_Date__c + 1` |

### 5.3 Custom Metadata: `Slack_Config__mdt`

**Label:** Slack Config
**Purpose:** Lưu Slack credentials — tránh hard code trong Apex class

| Field | API Name | Type | Notes |
|---|---|---|---|
| Bot Token | `Bot_Token__c` | Text(255) | Slack Bot token `xoxb-...` |
| Channel Id | `Channel_Id__c` | Text(18) | Slack channel ID `C0XXXXXXXX` |

**Record:** `Slack_Config.Default` — 1 record duy nhất, query bằng `LIMIT 1`

---

## 6. Apex Classes

### 6.1 `EmployeeSelector`

**Access:** `public with sharing`
**Purpose:** Data access layer cho Contact (Employee). Tách query ra khỏi business logic.

| Method | Signature | Returns | Description |
|---|---|---|---|
| getAllEmployees | `public static List<Contact> getAllEmployees()` | List\<Contact\> | Query tất cả Contact có RecordType = Employee, ORDER BY LastName |
| getEmployeeById | `public static Contact getEmployeeById(Id)` | Contact | Query 1 employee kèm sub-query Leave_Requests__r (LIMIT 5). Throw `LeaveException` nếu không tìm thấy |

**Inner class:** `LeaveException extends Exception`

### 6.2 `LeaveRequestService`

**Access:** `public with sharing`
**Purpose:** Business logic layer cho Leave Request.

| Method | Signature | Returns | Description |
|---|---|---|---|
| createLeaveRequest | `public static Leave_Request__c createLeaveRequest(Id, Date, Date, String)` | Leave_Request__c | Validate overlap → insert → return record. Throw nếu overlap |
| updateLeaveStatus | `public static Leave_Request__c updateLeaveStatus(Id, String, Id)` | Leave_Request__c | Validate status value → update Status + Approved_By → return record |

**Validation rules:**
- `createLeaveRequest`: kiểm tra không có đơn nào của cùng employee đang overlap (Status != `Rejected`)
- `updateLeaveStatus`: chỉ cho phép transition sang `Approved` hoặc `Rejected`

**Inner class:** `LeaveException extends Exception`

### 6.3 `SlackCalloutService`

**Access:** `public` (không dùng `with sharing` vì `@future`)
**Purpose:** HTTP callout đến Slack API khi trạng thái đơn thay đổi.

| Method | Signature | Description |
|---|---|---|
| notifyLeaveStatusChange | `@future(callout=true) public static void notifyLeaveStatusChange(Id)` | Query Leave_Request__c + Slack_Config__mdt → POST message lên Slack channel |

**Endpoint:** `https://slack.com/api/chat.postMessage`
**Auth:** `Authorization: Bearer {Bot_Token__c}`
**Message format:**
```
✅ Leave Request Approved
Employee: Nguyen Van A (a@company.com)
Period: 2026-06-10 → 2026-06-12
Reason: Annual leave
```

### 6.4 `CompanyManagementAPI`

**Access:** `global with sharing`
**Annotation:** `@RestResource(urlMapping='/company-management/v1/*')`
**Purpose:** Public REST API expose ra ngoài cho Postman / external systems.

#### Endpoints

| Method | URL | Description |
|---|---|---|
| GET | `/services/apexrest/company-management/v1/employees` | Lấy tất cả employees |
| GET | `/services/apexrest/company-management/v1/employees/{id}` | Lấy 1 employee kèm leave history |
| POST | `/services/apexrest/company-management/v1/leave-requests` | Tạo đơn nghỉ mới |
| PATCH | `/services/apexrest/company-management/v1/leave-requests/{id}` | Update status đơn nghỉ |

#### Request / Response

**POST /leave-requests — Request body:**
```json
{
  "employeeId": "003XXXXXXXXXXXXXXX",
  "startDate": "2026-06-10",
  "endDate": "2026-06-12",
  "reason": "Annual leave"
}
```

**POST /leave-requests — Response 201:**
```json
{
  "success": true,
  "leaveRequestId": "a00XXXXXXXXXXXXXXX",
  "status": "Pending",
  "message": "Leave request created successfully."
}
```

**PATCH /leave-requests/{id} — Request body:**
```json
{
  "status": "Approved"
}
```

**Error response format (4xx / 5xx):**
```json
{
  "success": false,
  "error": "Overlapping leave request already exists."
}
```

#### HTTP Status Codes

| Code | When |
|---|---|
| 200 | GET / PATCH thành công |
| 201 | POST tạo record thành công |
| 400 | Bad request, thiếu field bắt buộc, invalid status |
| 404 | Record không tìm thấy |
| 409 | Conflict — overlap leave request |
| 500 | Unexpected server error |

### 6.5 `LeaveRequestServiceTest`

**Annotation:** `@isTest`
**Coverage target:** ≥ 85% cho tất cả classes

| Test method | Scenario |
|---|---|
| `testCreateLeaveRequest_Success` | Tạo đơn thành công, assert Id != null, Status = Pending |
| `testCreateLeaveRequest_Overlap` | Tạo 2 đơn overlap, assert LeaveException thrown |
| `testApproveLeaveRequest` | Approve đơn, assert Status = Approved, Approved_By set |
| `testRestAPI_GetEmployees` | Mock REST context URI `/company-management/v1/employees`, assert statusCode = 200 |
| `testSlackCallout_Mock` | Dùng `HttpCalloutMock`, assert không throw exception |

---

## 7. Trigger

### `LeaveRequestTrigger`

**Object:** `Leave_Request__c`
**Events:** `after insert`, `after update`

**Logic:**
- `after insert` → call `SlackCalloutService.notifyLeaveStatusChange()` cho tất cả record mới
- `after update` → chỉ call khi `Status__c` thực sự thay đổi (so sánh với `Trigger.oldMap`)

---

## 8. Remote Site Settings

| Name | URL | Purpose |
|---|---|---|
| `Slack_API` | `https://slack.com` | Cho phép callout đến Slack API |

---

## 9. REST API — Authentication (Postman)

**Bước 1:** Tạo Connected App (xem mục 4.2)

**Bước 2:** Lấy access token

```
POST https://login.salesforce.com/services/oauth2/token
Content-Type: application/x-www-form-urlencoded

grant_type=password
client_id=YOUR_CONSUMER_KEY
client_secret=YOUR_CONSUMER_SECRET
username=your@email.com
password=YourPasswordYourSecurityToken
```

**Bước 3:** Dùng token trong mọi request

```
Authorization: Bearer {access_token}
Content-Type: application/json
```

**Base URL:** `https://YOUR_DEV_ORG.my.salesforce.com`

> Tip: Trong Postman, set `access_token` làm Collection Variable để dùng chung cho tất cả request trong collection.

---

## 10. Known Limitations (v1)

| Limitation | Notes |
|---|---|
| Không support half-day leave | `Days_Requested__c` tính theo nguyên ngày |
| Không xét timezone | Start/End Date là Date type, không có time |
| Overlap check chỉ theo ngày | Không phân biệt loại nghỉ (sick leave vs annual leave) |
| Slack token lưu trong Custom Metadata | Không encrypt — chỉ dùng cho môi trường dev/luyện tập |
| Không có pagination trong GET /employees | Trả toàn bộ, chưa có offset/limit |

---

## 11. SFDX Commands

```bash
# Setup
sf project generate --name com-mgt --default-package-dir force-app --manifest
sf org login web --alias com-mgt-dev --set-default

# Deploy
sf project deploy start --source-dir force-app/main/default

# Test
sf apex run test --class-names LeaveRequestServiceTest --synchronous --result-format human

# Pull từ org về local
sf project retrieve start --manifest manifest/package.xml

# Query data thử
sf data query --query "SELECT Id, Status__c, Employee__r.Name FROM Leave_Request__c"

# Chạy anonymous Apex
sf apex run --file scripts/test-create-leave.apex

# Xem org info (lấy URL, username)
sf org display --target-org com-mgt-dev
```

---

## 12. Git

### Setup

```bash
git init com-mgt
cd com-mgt
git remote add origin https://github.com/YOUR_USERNAME/com-mgt.git
git push -u origin develop
```

### `.gitignore`

```
.sf/
.sfdx/
*.log
node_modules/
.DS_Store
```

### Branch convention

| Branch | Purpose |
|---|---|
| `master` | Production-ready, chỉ merge từ `dev` |
| `dev` | Development chính |
| `feat/*` | Feature mới (ví dụ: `feat/leave-overlap-validation`) |
| `fix/*` | Bug fix (ví dụ: `fix/slack-callout-timeout`) |

### Commit message convention

```
feat: thêm GET /employees endpoint
fix: sửa lỗi overlap check khi End_Date = Start_Date
chore: update package.xml thêm RemoteSiteSetting
test: thêm test case cho reject leave request
docs: cập nhật REQUIREMENTS.md
```

---

## 13. Out of Scope (v1)

- LWC / Aura UI component
- Approval Process (Flow) tự động
- Platform Events / streaming
- Multi-org / sandbox promotion pipeline
- Email notifications (chỉ dùng Slack)
- Pagination cho REST API
- Half-day leave support
