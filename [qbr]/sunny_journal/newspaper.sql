CREATE TABLE IF NOT EXISTS `newspapers` (
  `journal_id` varchar(16) NOT NULL,
  `title` varchar(100) NOT NULL,
  `paper` varchar(50) NOT NULL DEFAULT '',
  `edition` int(11) NOT NULL DEFAULT 1,
  `author_name` varchar(100) NOT NULL,
  `author_citizenid` varchar(50) NOT NULL,
  `pages` longtext NOT NULL,
  `status` enum('draft','published') NOT NULL DEFAULT 'draft',
  `printed` int(11) NOT NULL DEFAULT 0,
  `created_at` timestamp NOT NULL DEFAULT current_timestamp(),
  `published_at` timestamp NULL DEFAULT NULL,
  PRIMARY KEY (`journal_id`),
  KEY `edition` (`edition`),
  KEY `status` (`status`),
  KEY `paper` (`paper`)
) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4 COLLATE=utf8mb4_general_ci;
