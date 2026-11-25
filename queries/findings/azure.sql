-- Output columns: control, cloud, account, region, resource_id, detail, gb
-- NSG rules are checked one at a time. A higher-priority Deny rule can override an Allow:
-- confirm with "effective security rules" in Azure before treating a hit as reachable.
with admin_ports(port) as (values (22), (1433), (3306), (3389), (5432)),
nsg_rules as (
  select n.subscription_id, n.region, n.resource_group || '/' || n.name as nsg,
         rule -> 'properties' as p
  from azure_network_security_group n,
       jsonb_array_elements(case when jsonb_typeof(n.security_rules) = 'array'
                                 then n.security_rules else '[]'::jsonb end) as rule
),
open_rules as (
  select *
  from nsg_rules
  where p ->> 'access' = 'Allow'
    and p ->> 'direction' = 'Inbound'
    and lower(p ->> 'protocol') in ('tcp', '*')
    and (lower(p ->> 'sourceAddressPrefix') in ('*', '0.0.0.0/0', 'internet', '::/0')
         or coalesce(p -> 'sourceAddressPrefixes', '[]'::jsonb) ?| array['*', '0.0.0.0/0', 'Internet', '::/0'])
),
port_ranges as (
  -- Azure stores ports in a single field, a list field, or both.
  select o.subscription_id, o.region, o.nsg, ports.range
  from open_rules o,
  lateral (
    select o.p ->> 'destinationPortRange' as range
    union all
    select jsonb_array_elements_text(coalesce(o.p -> 'destinationPortRanges', '[]'::jsonb))
  ) as ports
  where ports.range is not null and ports.range <> ''
)

select 'NET-01' as control, 'azure' as cloud, r.subscription_id as account, r.region,
       r.nsg as resource_id,
       'internet ingress to port(s) ' || array_to_string(array_agg(distinct a.port order by a.port), ', ') as detail,
       null::numeric as gb
from port_ranges r
join admin_ports a
  on case
       when r.range = '*' then true
       when r.range ~ '^[0-9]+-[0-9]+$' then a.port between split_part(r.range, '-', 1)::int
                                                      and split_part(r.range, '-', 2)::int
       when r.range ~ '^[0-9]+$' then a.port = r.range::int
       else false
     end
group by r.subscription_id, r.region, r.nsg

union all
-- This setting permits anonymous access. Each container still has its own access level.
select 'STO-02', 'azure', subscription_id, region, resource_group || '/' || name,
       'storage account permits anonymous blob access to be enabled on containers', null
from azure_storage_account
where allow_blob_public_access

union all
select 'DB-02', 'azure', s.subscription_id, s.region, s.resource_group || '/' || s.name,
       'SQL server firewall allows the whole IPv4 internet', null
from azure_sql_server s
where lower(s.public_network_access) = 'enabled'
  and exists (
    select 1
    from jsonb_array_elements(case when jsonb_typeof(s.firewall_rules) = 'array'
                                   then s.firewall_rules else '[]'::jsonb end) as f
    where f -> 'properties' ->> 'startIpAddress' = '0.0.0.0'
      and f -> 'properties' ->> 'endIpAddress' = '255.255.255.255')

union all
select 'DB-01', 'azure', s.subscription_id, s.region, s.resource_group || '/' || s.name,
       'SQL server public network access is enabled (firewall rules decide who can connect)', null
from azure_sql_server s
where lower(s.public_network_access) = 'enabled'

union all
select 'COST-01', 'azure', subscription_id, region, resource_group || '/' || name,
       'unattached disk, ' || disk_size_gb || ' GB', disk_size_gb
from azure_compute_disk
where disk_state = 'Unattached'

union all
-- NAT gateway addresses have no ip_configuration, so both attachments are checked.
-- Load balancer and other attachments appear as IP configurations. Verify before release.
select 'COST-02', 'azure', subscription_id, region, resource_group || '/' || name,
       'public IP with no IP configuration or NAT gateway', null
from azure_public_ip
where ip_configuration_id is null
  and (nat_gateway is null or jsonb_typeof(nat_gateway) = 'null')

union all
-- "stopped" is still billed for compute. "deallocated" is not.
select 'COST-03', 'azure', subscription_id, region, vm_id,
       name || ' is stopped but not deallocated', null
from azure_compute_virtual_machine
where power_state = 'stopped'

order by control, account, resource_id;
