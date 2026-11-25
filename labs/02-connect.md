# Lab 2: Connect Steampipe to your clouds (read-only)

Start with **one non-production account**. You can run any one cloud alone.

## 1. Install

```bash
# macOS
brew install turbot/tap/steampipe
# Linux or Windows WSL2 (read the script first if your policy requires it)
sudo /bin/sh -c "$(curl -fsSL https://steampipe.io/install/steampipe.sh)"

steampipe plugin install aws azure gcp
```

Run Steampipe as a normal user, not root. Check its licence terms with your legal team before wide deployment.

## 2. Grant read-only access

**AWS.** Deploy the role, then create a profile that assumes it.

```bash
aws cloudformation deploy --stack-name cloud-ledger-readonly \
  --template-file config/iam/aws-readonly-role.yaml --capabilities CAPABILITY_NAMED_IAM \
  --parameter-overrides TrustedPrincipalArn=arn:aws:iam::<RUNNER_ACCOUNT>:role/<RUNNER_ROLE>
```

```ini
# ~/.aws/config
[profile ledger-prod]
role_arn = arn:aws:iam::<ACCOUNT_ID>:role/cloud-ledger-readonly
source_profile = default
```

**Azure.**

```bash
az login
az role assignment create --assignee <PRINCIPAL_ID> --role Reader --scope /subscriptions/<SUBSCRIPTION_ID>
```

**Google Cloud.**

```bash
gcloud auth application-default login
for role in roles/viewer roles/iam.securityReviewer; do
  gcloud projects add-iam-policy-binding <PROJECT_ID> --member=<MEMBER> --role=$role
done
```

These are starting roles. If a query reports access denied, add only the missing permission.

## 3. Configure connections

Copy the files you need from `config/steampipe/` to `~/.steampipe/config/`. Edit the IDs and profiles. Each `connection "x_name"` is one account, subscription or project. The aggregator picks up every one that matches `x_*`. Remove the sample `aws_dev` block if you have one AWS account. If a plugin install created its own `connection "aws"`, `"azure"` or `"gcp"` block, replace that file so each name is defined once.

## 4. Start and collect

```bash
steampipe service start --show-password
export LEDGER_DB='<connection string it printed>'
LEDGER_CLOUDS=aws ./scripts/snapshot.sh      # or aws,azure,gcp
```

**Checkpoint:** every line shows a row count and none says `FAILED`.

**Then reconcile.** Compare the VM and bucket counts with each cloud console. A count that is too low usually means a missing region, account or permission. Do this before anyone relies on the report.

| Symptom | Check |
|---|---|
| `relation "aws_ec2_instance" does not exist` | Plugin installed? `.spc` file in place? Restart the service. |
| `AccessDenied` or `AuthorizationFailed` | The role assignment and the scope. |
| Some regions missing | `regions` in `aws.spc`. |
| A Google API "has not been used" | Enable that API in the project. |
| First run is slow | Normal for many regions. Narrow `regions` while testing. |
