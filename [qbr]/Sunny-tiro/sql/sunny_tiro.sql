CREATE TABLE IF NOT EXISTS `sunny_tiro_scores` (
    `citizenid` VARCHAR(80) NOT NULL,
    `player_name` VARCHAR(120) NOT NULL,
    `best_score` TINYINT UNSIGNED NOT NULL DEFAULT 0,
    `best_time_ms` INT UNSIGNED NULL,
    `best_shots` SMALLINT UNSIGNED NULL,
    `updated_at` TIMESTAMP NOT NULL DEFAULT CURRENT_TIMESTAMP ON UPDATE CURRENT_TIMESTAMP,
    PRIMARY KEY (`citizenid`),
    INDEX `idx_best_score` (`best_score` DESC)
) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4 COLLATE=utf8mb4_unicode_ci;
