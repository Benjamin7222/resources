-- Sunny_train : tables créées automatiquement au démarrage du resource.
-- Ce fichier sert uniquement à une installation manuelle.

CREATE TABLE IF NOT EXISTS `sunny_train_fleet` (
  `train_key` VARCHAR(64) NOT NULL,
  `condition` TINYINT UNSIGNED NOT NULL DEFAULT 100,
  `status` VARCHAR(24) NOT NULL DEFAULT 'auto',
  `last_inspection` INT UNSIGNED NULL DEFAULT NULL,
  `last_repair` INT UNSIGNED NULL DEFAULT NULL,
  `updated_by` VARCHAR(64) NULL DEFAULT NULL,
  `owned` TINYINT UNSIGNED NOT NULL DEFAULT 0,
  PRIMARY KEY (`train_key`)
) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4 COLLATE=utf8mb4_general_ci;

CREATE TABLE IF NOT EXISTS `sunny_train_tickets` (
  `serial` VARCHAR(20) NOT NULL,
  `citizenid` VARCHAR(64) NOT NULL,
  `holder_name` VARCHAR(128) NOT NULL DEFAULT '',
  `from_station` VARCHAR(64) NOT NULL,
  `to_station` VARCHAR(64) NOT NULL,
  `route` VARCHAR(255) NOT NULL,
  `class` VARCHAR(32) NOT NULL,
  `price` DECIMAL(10,2) NOT NULL DEFAULT 0,
  `issued_at` INT UNSIGNED NOT NULL,
  `expires_at` INT UNSIGNED NOT NULL,
  `used_at` INT UNSIGNED NULL DEFAULT NULL,
  `used_by` VARCHAR(64) NULL DEFAULT NULL,
  `departure_id` INT UNSIGNED NULL DEFAULT NULL,
  `depart_at` INT UNSIGNED NULL DEFAULT NULL,
  PRIMARY KEY (`serial`),
  KEY `idx_citizen` (`citizenid`),
  KEY `idx_expires` (`expires_at`)
) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4 COLLATE=utf8mb4_general_ci;

CREATE TABLE IF NOT EXISTS `sunny_train_departures` (
  `id` INT UNSIGNED NOT NULL AUTO_INCREMENT,
  `station` VARCHAR(64) NOT NULL,
  `destination` VARCHAR(64) NOT NULL,
  `train_key` VARCHAR(64) NULL DEFAULT NULL,
  `depart_at` INT UNSIGNED NOT NULL,
  `created_by` VARCHAR(64) NULL DEFAULT NULL,
  `created_name` VARCHAR(128) NOT NULL DEFAULT '',
  `status` VARCHAR(16) NOT NULL DEFAULT 'scheduled',
  `departed_at` INT UNSIGNED NULL DEFAULT NULL,
  `auto` TINYINT UNSIGNED NOT NULL DEFAULT 0,
  PRIMARY KEY (`id`),
  KEY `idx_status` (`status`, `depart_at`)
) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4 COLLATE=utf8mb4_general_ci;
-- Délais globaux des contrats (persistants après redémarrage).
CREATE TABLE IF NOT EXISTS `sunny_train_delivery_cooldowns` (
    `owner` VARCHAR(64) NOT NULL,
    `category` VARCHAR(128) NOT NULL,
    `expires_at` BIGINT NOT NULL DEFAULT 0,
    PRIMARY KEY (`owner`, `category`)
) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4;
