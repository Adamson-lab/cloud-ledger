-- AWS inventory in the shared column layout used by all three clouds.
-- Tag keys match without regard to case, '-', '_' or spaces: CostCenter = cost-center = cost_center.
select
  'aws' as cloud,
  account_id as account,
  region as region,
  'compute' as category,
  instance_id as resource_id,
  coalesce(title, instance_id) as name,
  instance_type as size,
  instance_state as state,
  'aws_ec2_instance' as source_table,
  (select t.value from jsonb_each_text(case when jsonb_typeof(tags) = 'object' then tags else '{}'::jsonb end) as t
    where regexp_replace(lower(t.key), '[-_ ]', '', 'g') in ('owner') and t.value <> '' order by t.key limit 1) as owner,
  (select t.value from jsonb_each_text(case when jsonb_typeof(tags) = 'object' then tags else '{}'::jsonb end) as t
    where regexp_replace(lower(t.key), '[-_ ]', '', 'g') in ('costcenter') and t.value <> '' order by t.key limit 1) as cost_center,
  (select t.value from jsonb_each_text(case when jsonb_typeof(tags) = 'object' then tags else '{}'::jsonb end) as t
    where regexp_replace(lower(t.key), '[-_ ]', '', 'g') in ('environment','env') and t.value <> '' order by t.key limit 1) as environment,
  true as taggable
from aws_ec2_instance
union all
select
  'aws' as cloud,
  account_id as account,
  region as region,
  'disk' as category,
  volume_id as resource_id,
  volume_id as name,
  size::text || ' GB' as size,
  state as state,
  'aws_ebs_volume' as source_table,
  (select t.value from jsonb_each_text(case when jsonb_typeof(tags) = 'object' then tags else '{}'::jsonb end) as t
    where regexp_replace(lower(t.key), '[-_ ]', '', 'g') in ('owner') and t.value <> '' order by t.key limit 1) as owner,
  (select t.value from jsonb_each_text(case when jsonb_typeof(tags) = 'object' then tags else '{}'::jsonb end) as t
    where regexp_replace(lower(t.key), '[-_ ]', '', 'g') in ('costcenter') and t.value <> '' order by t.key limit 1) as cost_center,
  (select t.value from jsonb_each_text(case when jsonb_typeof(tags) = 'object' then tags else '{}'::jsonb end) as t
    where regexp_replace(lower(t.key), '[-_ ]', '', 'g') in ('environment','env') and t.value <> '' order by t.key limit 1) as environment,
  true as taggable
from aws_ebs_volume
union all
select
  'aws' as cloud,
  account_id as account,
  region as region,
  'object_storage' as category,
  name as resource_id,
  name as name,
  null::text as size,
  null::text as state,
  'aws_s3_bucket' as source_table,
  (select t.value from jsonb_each_text(case when jsonb_typeof(tags) = 'object' then tags else '{}'::jsonb end) as t
    where regexp_replace(lower(t.key), '[-_ ]', '', 'g') in ('owner') and t.value <> '' order by t.key limit 1) as owner,
  (select t.value from jsonb_each_text(case when jsonb_typeof(tags) = 'object' then tags else '{}'::jsonb end) as t
    where regexp_replace(lower(t.key), '[-_ ]', '', 'g') in ('costcenter') and t.value <> '' order by t.key limit 1) as cost_center,
  (select t.value from jsonb_each_text(case when jsonb_typeof(tags) = 'object' then tags else '{}'::jsonb end) as t
    where regexp_replace(lower(t.key), '[-_ ]', '', 'g') in ('environment','env') and t.value <> '' order by t.key limit 1) as environment,
  true as taggable
from aws_s3_bucket
union all
select
  'aws' as cloud,
  account_id as account,
  region as region,
  'database' as category,
  db_instance_identifier as resource_id,
  db_instance_identifier as name,
  class as size,
  status as state,
  'aws_rds_db_instance' as source_table,
  (select t.value from jsonb_each_text(case when jsonb_typeof(tags) = 'object' then tags else '{}'::jsonb end) as t
    where regexp_replace(lower(t.key), '[-_ ]', '', 'g') in ('owner') and t.value <> '' order by t.key limit 1) as owner,
  (select t.value from jsonb_each_text(case when jsonb_typeof(tags) = 'object' then tags else '{}'::jsonb end) as t
    where regexp_replace(lower(t.key), '[-_ ]', '', 'g') in ('costcenter') and t.value <> '' order by t.key limit 1) as cost_center,
  (select t.value from jsonb_each_text(case when jsonb_typeof(tags) = 'object' then tags else '{}'::jsonb end) as t
    where regexp_replace(lower(t.key), '[-_ ]', '', 'g') in ('environment','env') and t.value <> '' order by t.key limit 1) as environment,
  true as taggable
from aws_rds_db_instance
union all
select
  'aws' as cloud,
  account_id as account,
  region as region,
  'public_ip' as category,
  allocation_id as resource_id,
  host(public_ip) as name,
  null::text as size,
  case when association_id is null then 'idle' else 'in_use' end as state,
  'aws_vpc_eip' as source_table,
  (select t.value from jsonb_each_text(case when jsonb_typeof(tags) = 'object' then tags else '{}'::jsonb end) as t
    where regexp_replace(lower(t.key), '[-_ ]', '', 'g') in ('owner') and t.value <> '' order by t.key limit 1) as owner,
  (select t.value from jsonb_each_text(case when jsonb_typeof(tags) = 'object' then tags else '{}'::jsonb end) as t
    where regexp_replace(lower(t.key), '[-_ ]', '', 'g') in ('costcenter') and t.value <> '' order by t.key limit 1) as cost_center,
  (select t.value from jsonb_each_text(case when jsonb_typeof(tags) = 'object' then tags else '{}'::jsonb end) as t
    where regexp_replace(lower(t.key), '[-_ ]', '', 'g') in ('environment','env') and t.value <> '' order by t.key limit 1) as environment,
  true as taggable
from aws_vpc_eip
order by category, account, name;
