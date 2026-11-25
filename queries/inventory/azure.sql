-- AZURE inventory in the shared column layout used by all three clouds.
-- Tag keys match without regard to case, '-', '_' or spaces: CostCenter = cost-center = cost_center.
select
  'azure' as cloud,
  subscription_id as account,
  region as region,
  'compute' as category,
  vm_id as resource_id,
  name as name,
  size as size,
  power_state as state,
  'azure_compute_virtual_machine' as source_table,
  (select t.value from jsonb_each_text(case when jsonb_typeof(tags) = 'object' then tags else '{}'::jsonb end) as t
    where regexp_replace(lower(t.key), '[-_ ]', '', 'g') in ('owner') and t.value <> '' order by t.key limit 1) as owner,
  (select t.value from jsonb_each_text(case when jsonb_typeof(tags) = 'object' then tags else '{}'::jsonb end) as t
    where regexp_replace(lower(t.key), '[-_ ]', '', 'g') in ('costcenter') and t.value <> '' order by t.key limit 1) as cost_center,
  (select t.value from jsonb_each_text(case when jsonb_typeof(tags) = 'object' then tags else '{}'::jsonb end) as t
    where regexp_replace(lower(t.key), '[-_ ]', '', 'g') in ('environment','env') and t.value <> '' order by t.key limit 1) as environment,
  true as taggable
from azure_compute_virtual_machine
union all
select
  'azure' as cloud,
  subscription_id as account,
  region as region,
  'disk' as category,
  resource_group || '/' || name as resource_id,
  name as name,
  disk_size_gb::text || ' GB' as size,
  disk_state as state,
  'azure_compute_disk' as source_table,
  (select t.value from jsonb_each_text(case when jsonb_typeof(tags) = 'object' then tags else '{}'::jsonb end) as t
    where regexp_replace(lower(t.key), '[-_ ]', '', 'g') in ('owner') and t.value <> '' order by t.key limit 1) as owner,
  (select t.value from jsonb_each_text(case when jsonb_typeof(tags) = 'object' then tags else '{}'::jsonb end) as t
    where regexp_replace(lower(t.key), '[-_ ]', '', 'g') in ('costcenter') and t.value <> '' order by t.key limit 1) as cost_center,
  (select t.value from jsonb_each_text(case when jsonb_typeof(tags) = 'object' then tags else '{}'::jsonb end) as t
    where regexp_replace(lower(t.key), '[-_ ]', '', 'g') in ('environment','env') and t.value <> '' order by t.key limit 1) as environment,
  true as taggable
from azure_compute_disk
union all
select
  'azure' as cloud,
  subscription_id as account,
  region as region,
  'object_storage' as category,
  resource_group || '/' || name as resource_id,
  name as name,
  sku_name as size,
  null::text as state,
  'azure_storage_account' as source_table,
  (select t.value from jsonb_each_text(case when jsonb_typeof(tags) = 'object' then tags else '{}'::jsonb end) as t
    where regexp_replace(lower(t.key), '[-_ ]', '', 'g') in ('owner') and t.value <> '' order by t.key limit 1) as owner,
  (select t.value from jsonb_each_text(case when jsonb_typeof(tags) = 'object' then tags else '{}'::jsonb end) as t
    where regexp_replace(lower(t.key), '[-_ ]', '', 'g') in ('costcenter') and t.value <> '' order by t.key limit 1) as cost_center,
  (select t.value from jsonb_each_text(case when jsonb_typeof(tags) = 'object' then tags else '{}'::jsonb end) as t
    where regexp_replace(lower(t.key), '[-_ ]', '', 'g') in ('environment','env') and t.value <> '' order by t.key limit 1) as environment,
  true as taggable
from azure_storage_account
union all
select
  'azure' as cloud,
  subscription_id as account,
  region as region,
  'database' as category,
  resource_group || '/' || name as resource_id,
  name as name,
  null::text as size,
  null::text as state,
  'azure_sql_server' as source_table,
  (select t.value from jsonb_each_text(case when jsonb_typeof(tags) = 'object' then tags else '{}'::jsonb end) as t
    where regexp_replace(lower(t.key), '[-_ ]', '', 'g') in ('owner') and t.value <> '' order by t.key limit 1) as owner,
  (select t.value from jsonb_each_text(case when jsonb_typeof(tags) = 'object' then tags else '{}'::jsonb end) as t
    where regexp_replace(lower(t.key), '[-_ ]', '', 'g') in ('costcenter') and t.value <> '' order by t.key limit 1) as cost_center,
  (select t.value from jsonb_each_text(case when jsonb_typeof(tags) = 'object' then tags else '{}'::jsonb end) as t
    where regexp_replace(lower(t.key), '[-_ ]', '', 'g') in ('environment','env') and t.value <> '' order by t.key limit 1) as environment,
  true as taggable
from azure_sql_server
union all
select
  'azure' as cloud,
  subscription_id as account,
  region as region,
  'public_ip' as category,
  resource_group || '/' || name as resource_id,
  name as name,
  null::text as size,
  case when ip_configuration_id is null and (nat_gateway is null or jsonb_typeof(nat_gateway) = 'null')
       then 'idle' else 'in_use' end as state,
  'azure_public_ip' as source_table,
  (select t.value from jsonb_each_text(case when jsonb_typeof(tags) = 'object' then tags else '{}'::jsonb end) as t
    where regexp_replace(lower(t.key), '[-_ ]', '', 'g') in ('owner') and t.value <> '' order by t.key limit 1) as owner,
  (select t.value from jsonb_each_text(case when jsonb_typeof(tags) = 'object' then tags else '{}'::jsonb end) as t
    where regexp_replace(lower(t.key), '[-_ ]', '', 'g') in ('costcenter') and t.value <> '' order by t.key limit 1) as cost_center,
  (select t.value from jsonb_each_text(case when jsonb_typeof(tags) = 'object' then tags else '{}'::jsonb end) as t
    where regexp_replace(lower(t.key), '[-_ ]', '', 'g') in ('environment','env') and t.value <> '' order by t.key limit 1) as environment,
  true as taggable
from azure_public_ip
order by category, account, name;
