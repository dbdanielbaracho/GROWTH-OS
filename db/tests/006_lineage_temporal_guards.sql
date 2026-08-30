-- Growth OS RC7 lineage/temporal regression contract.
-- Execute on PostgreSQL 18.6. PASS only from actual execution.

-- L1 publication lineage
-- self supersedes INSERT/UPDATE -> fail
-- cross-social-account predecessor -> fail
-- cross-content-version predecessor -> fail
-- same workspace/account/content predecessor -> succeed when other constraints permit

-- L2 content variants
-- source_content_version_id = variant_content_version_id INSERT/UPDATE -> fail

-- L3 insight demotion graph
-- direct self-cycle -> fail
-- A->B->A -> fail
-- A->B->C->A -> fail
-- acyclic A->B->C -> succeed

-- T1 experiment/exposure/outcome chronology
-- exposure eligibility before experiment.started_at -> fail
-- outcome.window_start before exposure eligibility -> fail
-- move exposure eligibility after existing outcome.window_start -> fail
-- move experiment.started_at after existing exposure eligibility -> fail
-- move experiment.ended_at before existing exposure activity -> fail
-- valid chronology -> succeed
