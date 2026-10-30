-- Migration 20261030000034: Purge mock un-timestamped bearings from registry
-- Eliminates mock XYZ test entries and resets un-timestamped CURRENTLY_IN records to NOT_ACTIVATED

-- 1. Remove mock XYZ bearings
delete from public.qr_codes
where model_number = 'XYZ'
   or bearing_id like 'PBI-SEC-XYZ%';

-- 2. Any bearing marked CURRENTLY_IN that has no recorded first_in_timestamp was never actually activated
update public.qr_codes
set current_lifecycle_state = 'NOT_ACTIVATED'
where current_lifecycle_state = 'CURRENTLY_IN'
  and first_in_timestamp is null;

