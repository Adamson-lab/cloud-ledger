-- GCP inventory in the shared column layout used by all three clouds.
-- Tag keys match without regard to case, '-', '_' or spaces: CostCenter = cost-center = cost_center.
select
  'gcp' as cloud,
  project as account,
  location as region,
  'compute' as category,
  id::text as resource_id,
  name as name,
  machine_type_name as size,
  status as state,
  'gcp_compute_instance' as source_table,
  (select t.value from jsonb_each_text(case when jsonb_typeof(labels) = 'object' then labels else '{}'::jsonb end) as t
    where regexp_replace(lower(t.key), '[-_ ]', '', 'g') in ('owner') and t.value <> '' order by t.key limit 1) as owner,
  (select t.value from jsonb_each_text(case when jsonb_typeof(labels) = 'object' then labels else '{}'::jsonb end) as t
    where regexp_replace(lower(t.key), '[-_ ]', '', 'g') in ('costcenter') and t.value <> '' order by t.key limit 1) as cost_center,
  (select t.value from jsonb_each_text(case when jsonb_typeof(labels) = 'object' then labels else '{}'::jsonb end) as t
    where regexp_replace(lower(t.key), '[-_ ]', '', 'g') in ('environment','env') and t.value <> '' order by t.key limit 1) as environment,
  true as taggable
from gcp_compute_instance
union all
select
  'gcp' as cloud,
  project as account,
  location as region,
  'disk' as category,
  location || '/' || name as resource_id,
  name as name,
  size_gb::bigint::text || ' GB' as size,
  status as state,
  'gcp_compute_disk' as source_table,
  (select t.value from jsonb_each_text(case when jsonb_typeof(labels) = 'object' then labels else '{}'::jsonb end) as t
    where regexp_replace(lower(t.key), '[-_ ]', '', 'g') in ('owner') and t.value <> '' order by t.key limit 1) as owner,
  (select t.value from jsonb_each_text(case when jsonb_typeof(labels) = 'object' then labels else '{}'::jsonb end) as t
    where regexp_replace(lower(t.key), '[-_ ]', '', 'g') in ('costcenter') and t.value <> '' order by t.key limit 1) as cost_center,
  (select t.value from jsonb_each_text(case when jsonb_typeof(labels) = 'object' then labels else '{}'::jsonb end) as t
    where regexp_replace(lower(t.key), '[-_ ]', '', 'g') in ('environment','env') and t.value <> '' order by t.key limit 1) as environment,
  true as taggable
from gcp_compute_disk
union all
select
  'gcp' as cloud,
  project as account,
  location as region,
  'object_storage' as category,
  name as resource_id,
  name as name,
  null::text as size,
  null::text as state,
  'gcp_storage_bucket' as source_table,
  (select t.value from jsonb_each_text(case when jsonb_typeof(labels) = 'object' then labels else '{}'::jsonb end) as t
    where regexp_replace(lower(t.key), '[-_ ]', '', 'g') in ('owner') and t.value <> '' order by t.key limit 1) as owner,
  (select t.value from jsonb_each_text(case when jsonb_typeof(labels) = 'object' then labels else '{}'::jsonb end) as t
    where regexp_replace(lower(t.key), '[-_ ]', '', 'g') in ('costcenter') and t.value <> '' order by t.key limit 1) as cost_center,
  (select t.value from jsonb_each_text(case when jsonb_typeof(labels) = 'object' then labels else '{}'::jsonb end) as t
    where regexp_replace(lower(t.key), '[-_ ]', '', 'g') in ('environment','env') and t.value <> '' order by t.key limit 1) as environment,
  true as taggable
from gcp_storage_bucket
union all
select
  'gcp' as cloud,
  project as account,
  location as region,
  'database' as category,
  name as resource_id,
  name as name,
  machine_type as size,
  state as state,
  'gcp_sql_database_instance' as source_table,
  (select t.value from jsonb_each_text(case when jsonb_typeof(labels) = 'object' then labels else '{}'::jsonb end) as t
    where regexp_replace(lower(t.key), '[-_ ]', '', 'g') in ('owner') and t.value <> '' order by t.key limit 1) as owner,
  (select t.value from jsonb_each_text(case when jsonb_typeof(labels) = 'object' then labels else '{}'::jsonb end) as t
    where regexp_replace(lower(t.key), '[-_ ]', '', 'g') in ('costcenter') and t.value <> '' order by t.key limit 1) as cost_center,
  (select t.value from jsonb_each_text(case when jsonb_typeof(labels) = 'object' then labels else '{}'::jsonb end) as t
    where regexp_replace(lower(t.key), '[-_ ]', '', 'g') in ('environment','env') and t.value <> '' order by t.key limit 1) as environment,
  true as taggable
from gcp_sql_database_instance
union all
select
  'gcp' as cloud,
  project as account,
  location as region,
  'public_ip' as category,
  location || '/' || name as resource_id,
  name as name,
  null::text as size,
  status as state,
  'gcp_compute_address' as source_table,
  null::text as owner,
  null::text as cost_center,
  null::text as environment,
  false as taggable
from gcp_compute_address
where address_type = 'EXTERNAL'
order by category, account, name;
