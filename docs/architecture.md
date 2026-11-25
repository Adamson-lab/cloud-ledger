# Architecture diagrams

GitHub draws these automatically.

## 1. System

```mermaid
flowchart LR
  subgraph clouds["Cloud control planes, read-only"]
    AWS["AWS APIs"]
    AZ["Azure APIs"]
    GCP["Google Cloud APIs"]
  end
  subgraph runner["Your runner, inside your network"]
    SP["Steampipe service<br/>PostgreSQL on 9193"]
    Q["queries/*.sql"]
    L["ledger.py"]
    S[("snapshots/*.json")]
  end
  AWS --> SP
  AZ --> SP
  GCP --> SP
  Q --> L
  L -- "SQL through psql" --> SP
  SP -- "rows" --> L
  L --> S
  S --> R["report.md"]
  S --> C["inventory.csv"]
  S --> D["dashboard.html"]
  S --> M["estate.md diagram"]
```

## 2. One collection run

```mermaid
sequenceDiagram
  participant O as Operator
  participant L as ledger.py
  participant S as Steampipe
  participant C as Cloud APIs
  O->>L: scripts/snapshot.sh
  loop each cloud, inventory then findings
    L->>S: SQL in a read-only session
    S->>C: List and Get calls
    alt access works
      C-->>S: resources
      S-->>L: rows as JSON
    else denied or unreachable
      C-->>S: error
      S-->>L: query fails
      L->>L: record the error, mark snapshot incomplete
    end
  end
  L-->>O: report, with changes since the last complete snapshot
```

## 3. Read-only access across many accounts

```mermaid
flowchart TB
  R["Runner identity"]
  R -- "sts:AssumeRole" --> A1["AWS prod<br/>cloud-ledger-readonly<br/>SecurityAudit"]
  R -- "sts:AssumeRole" --> A2["AWS dev<br/>cloud-ledger-readonly<br/>SecurityAudit"]
  R -- "Reader" --> Z["Azure subscription or management group"]
  R -- "Viewer and Security Reviewer" --> G["Google Cloud project or folder"]
```

## 4. Shared inventory model

```mermaid
erDiagram
  SNAPSHOT ||--o{ RESOURCE : lists
  SNAPSHOT ||--o{ FINDING : lists
  SNAPSHOT ||--o{ ERROR : records
  CONTROL ||--o{ FINDING : classifies
  RESOURCE {
    string cloud
    string account
    string region
    string category
    string resource_id
    string owner
    string cost_center
    string environment
  }
  FINDING {
    string control
    string cloud
    string account
    string resource_id
    string detail
  }
  CONTROL {
    string id
    string severity
    string fix
  }
```

## 5. How drift is decided

```mermaid
flowchart TD
  A["Two snapshots"] --> B{"Did both collect this cloud without errors?"}
  B -- "no" --> C["Not compared. Listed as skipped."]
  B -- "yes" --> D{"Finding present?"}
  D -- "only in new" --> E["New finding"]
  D -- "only in old" --> F["No longer reported"]
  D -- "in both" --> G["Still open"]
```

"No longer reported" is not proof of a fix. A narrower region list or a removed account has the same effect.

## 6. When AWS storage counts as public (STO-01)

```mermaid
flowchart TD
  A["S3 bucket"] --> B{"Does the bucket policy grant public access?"}
  B -- "no" --> N["No finding. ACLs are not checked."]
  B -- "yes" --> C{"restrict_public_buckets on?"}
  C -- "yes" --> M["No finding"]
  C -- "no" --> F["Critical finding. Check account-level Block Public Access."]
```
