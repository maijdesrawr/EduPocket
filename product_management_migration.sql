
USE centraldb;

DELIMITER $$

DROP PROCEDURE IF EXISTS edupocket_migrate_product_management$$
CREATE PROCEDURE edupocket_migrate_product_management()
BEGIN
    IF NOT EXISTS (
        SELECT 1 FROM information_schema.COLUMNS
        WHERE TABLE_SCHEMA = DATABASE()
          AND TABLE_NAME = 'products'
          AND COLUMN_NAME = 'stock_qty'
    ) THEN
        ALTER TABLE products
            ADD COLUMN stock_qty INT NOT NULL DEFAULT 0 AFTER price;
    END IF;

    IF NOT EXISTS (
        SELECT 1 FROM information_schema.COLUMNS
        WHERE TABLE_SCHEMA = DATABASE()
          AND TABLE_NAME = 'products'
          AND COLUMN_NAME = 'category'
    ) THEN
        ALTER TABLE products
            ADD COLUMN category VARCHAR(50) NOT NULL DEFAULT 'Uncategorized'
            AFTER stock_qty;
    END IF;

    UPDATE products
    SET category = 'Uncategorized'
    WHERE category IS NULL OR TRIM(category) = '';

    ALTER TABLE products
        MODIFY COLUMN category VARCHAR(50) NOT NULL DEFAULT 'Uncategorized';

    IF NOT EXISTS (
        SELECT 1 FROM information_schema.STATISTICS
        WHERE TABLE_SCHEMA = DATABASE()
          AND TABLE_NAME = 'products'
          AND INDEX_NAME = 'ix_products_catalog'
    ) THEN
        CREATE INDEX ix_products_catalog
            ON products (canteen_id, is_active, category, name);
    END IF;

    IF EXISTS (
        SELECT 1 FROM information_schema.TABLES
        WHERE TABLE_SCHEMA = DATABASE()
          AND TABLE_NAME = 'transaction_items'
    ) AND EXISTS (
        SELECT 1 FROM information_schema.COLUMNS
        WHERE TABLE_SCHEMA = DATABASE()
          AND TABLE_NAME = 'transaction_items'
          AND COLUMN_NAME = 'item_name'
    ) AND EXISTS (
        SELECT 1 FROM information_schema.COLUMNS
        WHERE TABLE_SCHEMA = DATABASE()
          AND TABLE_NAME = 'transactions'
          AND COLUMN_NAME = 'description'
    ) THEN
        SET @pm_description_backfill =
            'UPDATE transactions t '
            'JOIN ('
            ' SELECT transaction_id, '
            ' GROUP_CONCAT('
            '   CONCAT(TRIM(item_name), '' '', quantity, ''x'') '
            '   ORDER BY product_id ASC, id ASC SEPARATOR '', '''
            ' ) AS authoritative_description, '
            ' SUM(CASE WHEN item_name IS NULL OR TRIM(item_name) = '''' '
            '          OR quantity <= 0 THEN 1 ELSE 0 END) AS invalid_items '
            ' FROM transaction_items GROUP BY transaction_id'
            ') item_summary ON item_summary.transaction_id = t.transaction_id '
            'SET t.description = item_summary.authoritative_description '
            'WHERE t.transaction_type = ''payment'' '
            'AND LOWER(TRIM(COALESCE(t.description, ''''))) '
            '    IN ('''', ''canteen purchase'') '
            'AND item_summary.invalid_items = 0 '
            'AND CHAR_LENGTH(item_summary.authoritative_description) BETWEEN 1 AND 255';
        PREPARE pm_description_statement FROM @pm_description_backfill;
        EXECUTE pm_description_statement;
        DEALLOCATE PREPARE pm_description_statement;
    END IF;
END$$

CALL edupocket_migrate_product_management()$$
DROP PROCEDURE edupocket_migrate_product_management$$

DELIMITER ;
