# Lab 3: Create a risk, detect it, fix it

**Use a sandbox account you are allowed to change.** These commands create resources, so you need your own write credentials. Steampipe keeps using the read-only role. Each rule below protects nothing, because no machine uses it. Some organisations block these rules by policy or alert on them, so tell your security team first.

Do the three steps for each cloud you connected: **create**, **collect**, **delete and collect again**.

Steampipe caches results for a few minutes. Run `steampipe service restart` before each collection so you see current data.

## AWS

```bash
SG=$(aws ec2 create-security-group --group-name ledger-lab --description "cloud-ledger lab" --query GroupId --output text)
aws ec2 authorize-security-group-ingress --group-id $SG --protocol tcp --port 22 --cidr 0.0.0.0/0
# collect: expect NET-01 for $SG
aws ec2 delete-security-group --group-id $SG
```

This needs a default VPC. Without one, add `--vpc-id` to the first command.

## Azure

```bash
az group create -n rg-ledger-lab -l westeurope
az network nsg create -g rg-ledger-lab -n nsg-ledger-lab
az network nsg rule create -g rg-ledger-lab --nsg-name nsg-ledger-lab -n lab-ssh --priority 100 \
  --access Allow --direction Inbound --protocol Tcp --source-address-prefixes '*' --destination-port-ranges 22
# collect: expect NET-01 for rg-ledger-lab/nsg-ledger-lab
az group delete -n rg-ledger-lab --yes
```

## Google Cloud

```bash
gcloud compute networks create ledger-lab-net --subnet-mode=custom
gcloud compute firewall-rules create ledger-lab-ssh --network=ledger-lab-net --allow=tcp:22 --source-ranges=0.0.0.0/0
# collect: expect NET-01 for ledger-lab-ssh
gcloud compute firewall-rules delete ledger-lab-ssh --quiet
gcloud compute networks delete ledger-lab-net --quiet
```

**Checkpoint:** the first report lists the finding under "New finding". The report after deletion lists it under "No longer reported". The first comparison needs an earlier snapshot, so run Lab 2 first.
