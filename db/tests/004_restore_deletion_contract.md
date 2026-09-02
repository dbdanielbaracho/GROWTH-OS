# Restore/deletion execution test (requires backup/restore harness)

Required PASS sequence:
1. Create workspace + tenant-owned rows + media/search/vector/log test artifacts.
2. Create deletion_request and tombstone; verify customer read path denies immediately.
3. Complete primary purge jobs; verify source tables/artifacts are gone or inaccessible.
4. Restore a backup taken before the deletion into quarantine.
5. Replay deletion ledger/tombstones before enabling serving.
6. Verify the deleted workspace cannot be read from restored primary, read replica, object/CDN simulation, vector/search and exported cache fixtures.
7. Only then mark restore eligible to serve.

This test is NOT executable from SQL alone; it belongs to the operational restore harness. Do not mark PASS without an actual restore run.
