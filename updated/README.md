# Updated XAMPP backend

This folder contains the current PHP backend copied from `C:\xampp\htdocs\edupay`.

## Install

1. Copy the contents of `updated/edupay` to `C:\xampp\htdocs\edupay`.
2. Copy `updated/edupocket-config/database.example.php` to
   `C:\xampp\edupocket-config\database.php` and fill in local database values.
3. Copy `updated/edupocket-config/security.example.php` to
   `C:\xampp\edupocket-config\security.php` and fill in local secrets.
4. Create `C:\xampp\edupocket-config\master.key` locally. Never commit the key.
5. Apply the SQL migrations from the repository to the local database.
6. Run `C:\xampp\php\php.exe C:\xampp\htdocs\edupay\migrate_account_history.php`
   before using account deletion. This repeatable migration preserves student
   transactions and top-ups when their account is deleted.

The following runtime/private data is deliberately not distributed through Git:

- live credentials and encryption keys;
- database backups and dumps containing application data;
- uploaded user files;
- debug logs.
