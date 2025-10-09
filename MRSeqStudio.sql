--
-- Create database if it doesn't exist
CREATE DATABASE IF NOT EXISTS MRSeqStudio CHARACTER SET utf8mb4 COLLATE utf8mb4_unicode_ci;

-- Select it to work on it
USE MRSeqStudio;

--
-- Table structure for table `daily_sequence_usage`
--

CREATE TABLE `daily_sequence_usage` (
  `id` int(11) NOT NULL,
  `user_id` int(11) NOT NULL,
  `date` date NOT NULL,
  `sequences_used` int(11) NOT NULL DEFAULT 0
) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4 COLLATE=utf8mb4_unicode_ci;


--
-- Table structure for table `results`
--

CREATE TABLE `results` (
  `id` int(11) NOT NULL,
  `user_id` int(11) NOT NULL,
  `sequence_id` varchar(100) NOT NULL,
  `file_path` varchar(255) NOT NULL,
  `file_size_mb` float NOT NULL,
  `created_at` datetime DEFAULT current_timestamp(),
  `sequence_path` varchar(200) NOT NULL DEFAULT 'None'
) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4 COLLATE=utf8mb4_unicode_ci;

--

--
-- Table structure for table `users`
--

CREATE TABLE `users` (
  `id` int(11) NOT NULL,
  `username` varchar(50) NOT NULL,
  `email` varchar(100) NOT NULL,
  `password_hash` varchar(255) NOT NULL,
  `is_premium` tinyint(1) NOT NULL DEFAULT 0,
  `created_at` datetime DEFAULT current_timestamp(),
  `updated_at` datetime DEFAULT current_timestamp() ON UPDATE current_timestamp(),
  `is_admin` tinyint(1) NOT NULL DEFAULT 0
) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4 COLLATE=utf8mb4_unicode_ci;


--
-- Table structure for table `user_privileges`
--

CREATE TABLE `user_privileges` (
  `user_id` int(11) NOT NULL,
  `gpu_access` tinyint(1) NOT NULL DEFAULT 0,
  `max_daily_sequences` int(11) NOT NULL DEFAULT 10,
  `storage_quota_mb` float NOT NULL DEFAULT 0.5
) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4 COLLATE=utf8mb4_unicode_ci;
--
-- Table structure for table `sequences`
--
CREATE TABLE `sequences` (
  `id` int(11) NOT NULL,
  `user_id` int(11) NOT NULL,
  `sequence_id` varchar(100) NOT NULL,
  `date` date NOT NULL,
  `created_at` datetime DEFAULT current_timestamp()
) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4 COLLATE=utf8mb4_unicode_ci;

--

--
-- Indices de la tabla `daily_sequence_usage`
--
ALTER TABLE `daily_sequence_usage`
  ADD PRIMARY KEY (`id`),
  ADD UNIQUE KEY `unique_user_date` (`user_id`,`date`);

--
-- Indexes for table `results`
--
ALTER TABLE `results`
  ADD PRIMARY KEY (`id`),
  ADD KEY `user_id` (`user_id`),
  ADD KEY `sequence_id_idx` (`sequence_id`),
  ADD KEY `created_at_idx` (`created_at`);

--
-- Indices de la tabla `users`
--
ALTER TABLE `users`
  ADD PRIMARY KEY (`id`),
  ADD UNIQUE KEY `username` (`username`),
  ADD UNIQUE KEY `email` (`email`);

--
-- Indexes for table `user_privileges`
--
ALTER TABLE `user_privileges`
  ADD PRIMARY KEY (`user_id`);
--
-- Indexes for table `sequences`
--
ALTER TABLE `sequences`
  ADD PRIMARY KEY (`id`),
  ADD KEY `user_id` (`user_id`),
  ADD KEY `sequence_id_idx` (`sequence_id`),
  ADD KEY `date_idx` (`date`);

--
-- AUTO_INCREMENT for dumped tables
--

--
-- AUTO_INCREMENT de la tabla `daily_sequence_usage`
--
ALTER TABLE `daily_sequence_usage`
  MODIFY `id` int(11) NOT NULL AUTO_INCREMENT, AUTO_INCREMENT=18;

--
-- AUTO_INCREMENT de la tabla `results`
--
ALTER TABLE `results`
  MODIFY `id` int(11) NOT NULL AUTO_INCREMENT, AUTO_INCREMENT=139;

--
-- AUTO_INCREMENT for table `users`
--
ALTER TABLE `users`
  MODIFY `id` int(11) NOT NULL AUTO_INCREMENT, AUTO_INCREMENT=12;
--
-- AUTO_INCREMENT for table `sequences`
--
ALTER TABLE `sequences`
  MODIFY `id` int(11) NOT NULL AUTO_INCREMENT;

--
-- Constraints for dumped tables
--

--
-- Filtros para la tabla `daily_sequence_usage`
--
ALTER TABLE `daily_sequence_usage`
  ADD CONSTRAINT `daily_sequence_usage_ibfk_1` FOREIGN KEY (`user_id`) REFERENCES `users` (`id`) ON DELETE CASCADE;

--
-- Constraints for table `results`
--
ALTER TABLE `results`
  ADD CONSTRAINT `results_ibfk_1` FOREIGN KEY (`user_id`) REFERENCES `users` (`id`) ON DELETE CASCADE;

--
-- Constraints for table `user_privileges`
--
ALTER TABLE `user_privileges`
  ADD CONSTRAINT `user_privileges_ibfk_1` FOREIGN KEY (`user_id`) REFERENCES `users` (`id`) ON DELETE CASCADE;
--
-- Constraints for table `sequences`
--
ALTER TABLE `sequences`
  ADD CONSTRAINT `sequences_ibfk_1` FOREIGN KEY (`user_id`) REFERENCES `users` (`id`) ON DELETE CASCADE;
--
-- Convenience views exposing usernames with results and sequences
--
CREATE OR REPLACE VIEW `results_with_user` AS
  SELECT r.id, r.user_id, u.username, r.sequence_id, r.file_path, r.file_size_mb, r.created_at, r.sequence_path
  FROM results r
  JOIN users u ON u.id = r.user_id;

CREATE OR REPLACE VIEW `sequences_with_user` AS
  SELECT s.id, s.user_id, u.username, s.sequence_id, s.`date`, s.created_at
  FROM sequences s
  JOIN users u ON u.id = s.user_id;
COMMIT;
