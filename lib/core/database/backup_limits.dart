/// Shared by export and restore. A file over this size is refused before it
/// is written, and the same ceiling is enforced when reading a file back.
const maxBackupBytes = 50 * 1024 * 1024;

/// Review logs are the table that fills a backup. A compact row is about
/// 320 bytes, so 50 MB holds roughly 160,000 of them. The cap stays above
/// that count so a file accepted by [maxBackupBytes] is not rejected here.
const maxBackupRowsPerTable = 200000;
