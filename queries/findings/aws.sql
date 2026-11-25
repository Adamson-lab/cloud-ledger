-- Output columns: control, cloud, account, region, resource_id, detail, gb
with admin_ports(port) as (values (22), (1433), (3306), (3389), (5432))

select 'NET-01' as control, 'aws' as cloud, r.account_id as account, r.region,
       r.group_id as resource_id,
       'internet ingress to port(s) ' || array_to_string(array_agg(distinct p.port order by p.port), ', ') as detail,
       null::numeric as gb
from aws_vpc_security_group_rule r
join admin_ports p
  on r.ip_protocol = '-1'
  or (r.ip_protocol = 'tcp' and p.port between r.from_port and r.to_port)
where not r.is_egress
  and (r.cidr_ipv4 = '0.0.0.0/0'::cidr or r.cidr_ipv6 = '::/0'::cidr)
group by r.account_id, r.region, r.group_id

union all
-- A public bucket policy takes effect unless restrict_public_buckets blocks it.
-- Account-level Block Public Access and object ACLs are NOT evaluated here.
select 'STO-01', 'aws', account_id, region, name, 'bucket policy grants public access', null
from aws_s3_bucket
where bucket_policy_is_public and not coalesce(restrict_public_buckets, false)

union all
select 'DB-01', 'aws', account_id, region, db_instance_identifier,
       'RDS instance is publicly accessible (security groups decide who can connect)', null
from aws_rds_db_instance
where publicly_accessible

union all
select 'ENC-01', 'aws', account_id, region, volume_id, 'EBS volume is not encrypted', null
from aws_ebs_volume
where not encrypted

union all
select 'COST-01', 'aws', account_id, region, volume_id, 'unattached volume, ' || size || ' GB', size
from aws_ebs_volume
where state = 'available'

union all
select 'COST-02', 'aws', account_id, region, allocation_id, 'Elastic IP with no association', null
from aws_vpc_eip
where association_id is null

order by control, account, resource_id;
