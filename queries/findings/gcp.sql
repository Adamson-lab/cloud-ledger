-- Output columns: control, cloud, account, region, resource_id, detail, gb
-- Hierarchical firewall policies, deny rules and rule priority are NOT evaluated.
with admin_ports(port) as (values (22), (1433), (3306), (3389), (5432)),
open_allow as (
  select f.project, f.name, a
  from gcp_compute_firewall f,
       jsonb_array_elements(case when jsonb_typeof(f.allowed) = 'array'
                                 then f.allowed else '[]'::jsonb end) as a
  where f.direction = 'INGRESS'
    and not coalesce(f.disabled, false)
    and f.source_ranges ?| array['0.0.0.0/0', '::/0']
    and lower(a ->> 'IPProtocol') in ('tcp', 'all')
)

select 'NET-01' as control, 'gcp' as cloud, o.project as account, 'global' as region,
       o.name as resource_id,
       'internet ingress to port(s) ' || array_to_string(array_agg(distinct p.port order by p.port), ', ') as detail,
       null::numeric as gb
from open_allow o
join admin_ports p
  on o.a -> 'ports' is null   -- no port list means every port
  or exists (
    select 1 from jsonb_array_elements_text(o.a -> 'ports') as r
    where p.port between split_part(r, '-', 1)::int
                     and coalesce(nullif(split_part(r, '-', 2), ''), split_part(r, '-', 1))::int)
group by o.project, o.name

union all
select 'STO-01', 'gcp', b.project, b.location, b.name, 'bucket IAM policy grants access to the public', null
from gcp_storage_bucket b
where coalesce(b.iam_configuration_public_access_prevention, '') <> 'enforced'
  and exists (
    select 1
    from jsonb_array_elements(coalesce(b.iam_policy -> 'bindings', '[]'::jsonb)) as binding
    where binding -> 'members' ?| array['allUsers', 'allAuthenticatedUsers'])

union all
select 'DB-02', 'gcp', d.project, d.location, d.name,
       'Cloud SQL authorised networks include the whole internet', null
from gcp_sql_database_instance d
where (d.ip_configuration ->> 'ipv4Enabled')::boolean
  and exists (
    select 1
    from jsonb_array_elements(coalesce(d.ip_configuration -> 'authorizedNetworks', '[]'::jsonb)) as n
    where n ->> 'value' = '0.0.0.0/0')

union all
select 'DB-01', 'gcp', project, location, name,
       'Cloud SQL has a public IPv4 address', null
from gcp_sql_database_instance
where (ip_configuration ->> 'ipv4Enabled')::boolean

union all
select 'COST-01', 'gcp', project, location, location || '/' || name,
       'unattached disk, ' || size_gb::bigint || ' GB', size_gb::numeric
from gcp_compute_disk
where users is null or jsonb_typeof(users) = 'null' or users = '[]'::jsonb

union all
select 'COST-02', 'gcp', project, location, location || '/' || name,
       'reserved external IP that nothing uses', null
from gcp_compute_address
where address_type = 'EXTERNAL' and status = 'RESERVED'

order by control, account, resource_id;
