-- This is a semi-relaxed search and as such some need to match while others may or may not match.

-- These modify the limits of MySQL in order to maximize performance of this query which can be slow.
SET tmp_table_size=524288000;
SET max_heap_table_size=524288000;

-- These are variables storing the query parameters for easy replication throughout the query.
SET @global   := 'lapto*';
SET @staff    := 'vlad*';
SET @client   := 'lapto*';
SET @pstatus  := '1,2,3';
SET @tstatus  := '0,1';
SET @before   := '2014-12-31';
SET @after    := '2014-02-01';
SET @attached := 0;

-- The projects query.
(
  SELECT
      'p' AS `type`,
      (
       -- FIND_IN_SET() is used here to detect if there is an exact project id match. IN() does not work as the variable is of string type.
       -- Since this is a relevance search system we assign a high relevance to any matches to put it on top.
       IF(FIND_IN_SET(`k`.`id`, @global), 100, 0) +

       -- This will try to do full and partial match for the project name and threads subjects against the global keywords.
       -- The first part will match any exact matches and give out a decimal relevance value.
       -- The second (with IN BOOLEAN MODE) will also do partial matches if each keyword is followed by a * and return a 0 or 1.
       -- For WHERE and ON clauses use just the partial condition to speed things up.
       -- Does not really make sense but this is how it works.
       MATCH(`p`.`name`)    AGAINST(@global) + MATCH(`p`.`name`)    AGAINST(@global IN BOOLEAN MODE) +
       MATCH(`t`.`subject`) AGAINST(@global) + MATCH(`t`.`subject`) AGAINST(@global IN BOOLEAN MODE) +

       -- These two are already calculated in the sub query so we just add them along.
       `n`.`match` + `n`.`bool` + 
       `a`.`match` + `a`.`bool` + 

       -- This will try to do full and partial match for the project task names.
       MATCH(`k`.`name`) AGAINST(@global) + MATCH(`k`.`name`)    AGAINST(@global IN BOOLEAN MODE) +

       -- This will try to do full and partial match for the project client and staff names.
       MATCH(`c`.`name`) AGAINST(@global) + MATCH(`c`.`name`) AGAINST(@global IN BOOLEAN MODE) + ( MATCH(`c`.`name`) AGAINST(@client) + MATCH(`c`.`name`) AGAINST(@client IN BOOLEAN MODE) ) * 10  +
       MATCH(`m`.`name`) AGAINST(@global) + MATCH(`m`.`name`) AGAINST(@global IN BOOLEAN MODE) + ( MATCH(`m`.`name`) AGAINST(@staff)  + MATCH(`m`.`name`) AGAINST(@staff IN BOOLEAN MODE) )  * 10  +
       0 -- this makes it easy to fiddle with the above
      ) AS `relevance`,

      -- Here we select the project ID
      `p`.`id` AS `pid`,

      -- Since we do not want the same project replicated multiple times we do some fancy concatenations:
      -- Merge thread IDs.
      GROUP_CONCAT(DISTINCT `t`.`id`) AS `tids`,
      -- Merge note IDs together with their respective thread ID. Colon separated.
      GROUP_CONCAT(DISTINCT CONCAT(`n`.`id`, ':', `n`.`thread_id`)) AS `nids`,
      -- Merge note attachments IDs together with their respective note ID and thread ID. Colon separated.
      GROUP_CONCAT(DISTINCT CONCAT(`a`.`id`, ':', `a`.`note_id`, ':', `a`.`thread_id`)) AS `aids`,
      -- Merge task IDs.
      GROUP_CONCAT(DISTINCT `k`.`id`) AS `kids`,

      -- This is above relevance replicated to isolate each one and provide a more selective relevance ordering.
      MATCH(`p`.`name`)    AGAINST(@global) + MATCH(`p`.`name`)    AGAINST(@global IN BOOLEAN MODE) AS `p`,
      MATCH(`t`.`subject`) AGAINST(@global) + MATCH(`t`.`subject`) AGAINST(@global IN BOOLEAN MODE) AS `t`,
      `n`.`match` + `n`.`bool` AS `n`,
      `a`.`match` + `a`.`bool` AS `a`,
      MATCH(`k`.`name`)    AGAINST(@global) + MATCH(`k`.`name`)    AGAINST(@global IN BOOLEAN MODE) AS `k`,

      MATCH(`c`.`name`) AGAINST(@global) + MATCH(`c`.`name`) AGAINST(@global IN BOOLEAN MODE) + ( MATCH(`c`.`name`) AGAINST(@client) + MATCH(`c`.`name`) AGAINST(@client IN BOOLEAN MODE) ) * 10 AS `c`,
      MATCH(`m`.`name`) AGAINST(@global) + MATCH(`m`.`name`) AGAINST(@global IN BOOLEAN MODE) + ( MATCH(`m`.`name`) AGAINST(@staff)  + MATCH(`m`.`name`) AGAINST(@staff IN BOOLEAN MODE)  ) * 10 AS `m`

    -- The target table.
    FROM `projects` AS `p`
      -- Basic join on subscribers.
      LEFT JOIN `projects_subscribers`        AS `s` ON `s`.`project_id` = `p`.`id`
      -- Matching join on threads that contain one or more keywords only. Since we show for each result what threads matched as well this eliminates the ones that don't match.
      LEFT JOIN `projects_threads`            AS `t` ON `t`.`project_id` = `p`.`id` AND ( MATCH(`t`.`subject`) AGAINST(@global) OR MATCH(`t`.`subject`) AGAINST(@global IN BOOLEAN MODE) )
      -- Another matching join but this time on a sub query as this increases performance by eliminating the useless text fields which would consume memory.
      -- This also has date matching if dates specified.
      LEFT JOIN (
                 SELECT
                     `sn`.`id`,
                     `sn`.`project_id`,
                     `sn`.`thread_id`,
                     MATCH(`sn`.`notes`) AGAINST(@global) AS `match`,
                     MATCH(`sn`.`notes`) AGAINST(@global IN BOOLEAN MODE) AS `bool`
                   FROM `projects_notes` AS `sn`
                   WHERE 
                     MATCH(`sn`.`notes`) AGAINST(@global IN BOOLEAN MODE)
                 AND (@before = '' OR `sn`.`datetime` < @before)
                 AND (@after = '' OR `sn`.`datetime` > @after)
                ) AS `n` ON `n`.`project_id` = `p`.`id`
      -- Another matching join but this time on a sub query as this increases performance by eliminating the useless binary blob fields which would consume memory.
      -- Not sure why someone thought it was a good idea to store binaries in the database.
      -- This joins only if set to do so by the @attached variable.
      LEFT JOIN (
                 SELECT
                     `sa`.`id`,
                     `sa`.`project_id`,
                     `sa`.`thread_id`,
                     `sa`.`note_id`,
                     MATCH(`sa`.`name`) AGAINST(@global) AS `match`,
                     MATCH(`sa`.`name`) AGAINST(@global IN BOOLEAN MODE) AS `bool`
                   FROM `projects_files` AS `sa`
                   WHERE 
                     @attached > 0
                 AND MATCH(`sa`.`name`) AGAINST(@global IN BOOLEAN MODE)
                ) AS `a` ON `a`.`project_id` = `p`.`id`
      -- Matching join on tasks that contain one or more keywords only. Since we show for each result what tasks matched as well this eliminates the ones that don't match.
      -- This will also check for ID match as alternative to keyword match.
      -- Also it will do staff status if any specified.
      LEFT JOIN `tasks`                       AS `k` ON `k`.`project_id` = `p`.`id` AND ( MATCH(`k`.`name`) AGAINST(@global IN BOOLEAN MODE) OR `k`.`id` IN (@global) OR `k`.`staff_id` = @staff ) AND FIND_IN_SET(`k`.`status`, @pstatus)
      -- Basic join on clients.
      LEFT JOIN `clients`                     AS `c` ON `c`.`id` = `p`.`client_id`
      -- Dual join on staff assigned or subscribed.
      LEFT JOIN `staff`                       AS `m` ON `m`.`id` = `s`.`staff_id` OR `m`.`id` = `k`.`staff_id`

    WHERE
      TRUE -- This helps fiddle with below and does not really impact performance.

      -- Ensure there is at least one match in at least one of the project related tables (not staff or client).
      AND (
           `p`.`id` IS NOT NULL
        OR `t`.`id` IS NOT NULL
        OR `n`.`id` IS NOT NULL
        OR `a`.`id` IS NOT NULL
        OR `k`.`id` IS NOT NULL
           )
      -- If staff empty keep those who's names match in the global search or are assigned or subscribed.
      -- I know this might not make much sense but consider that someone might not use the advanced filter and search for staff in the global keywords.
      AND (
           @staff = ''
        -- Now that I look at below I think perhaps it should be != 0
        -- Change if issues reported.
        OR (@staff = '' AND (MATCH(`m`.`name`) AGAINST(@global) OR MATCH(`m`.`name`) AGAINST(@global IN BOOLEAN MODE)))
        OR MATCH(`m`.`name`) AGAINST(@staff)
        OR MATCH(`m`.`name`) AGAINST(@staff IN BOOLEAN MODE)
           )
      -- As above for client.
      AND (
           @client = ''
        OR (@client = '' AND (MATCH(`c`.`name`) AGAINST(@global) OR MATCH(`c`.`name`) AGAINST(@global IN BOOLEAN MODE)))
        OR MATCH(`c`.`name`) AGAINST(@client)
        OR MATCH(`c`.`name`) AGAINST(@client IN BOOLEAN MODE)
           )
      -- If dates given filter for those that match in the tables that have a date field.
      AND (
           @before = ''
        OR `p`.`date` < @before
        OR `t`.`date_created` < @before
        OR `n`.`id` IS NOT NULL
        OR `k`.`date` < @before
           )
      AND (
           @after = ''
        OR `p`.`date` > @after
        OR `t`.`date_created` > @after
        OR `n`.`id` IS NOT NULL
        OR `k`.`date` > @after
           )
      -- Final filter this ensures at least one of the given parameters matches at least in one place.
      AND (
           `p`.`id` IN (@global)
        OR `k`.`id` IN (@global)
        OR @client != ''
        OR @staff != ''

        OR MATCH(`p`.`name`)    AGAINST(@global) OR MATCH(`p`.`name`)    AGAINST(@global IN BOOLEAN MODE)
        OR MATCH(`t`.`subject`) AGAINST(@global) OR MATCH(`t`.`subject`) AGAINST(@global IN BOOLEAN MODE)
        OR `n`.`id` IS NOT NULL
        OR `a`.`id` IS NOT NULL
        OR MATCH(`k`.`name`)    AGAINST(@global) OR MATCH(`k`.`name`)    AGAINST(@global IN BOOLEAN MODE)
           )
    
    -- Group here to ensure proper concatenation in the selects.
    GROUP BY `p`.`id`
)

UNION ALL

-- The tickets query.
-- Same as in the above but different tables and fields and slightly less complex.
-- If you understand the above this should require no comments.
(
  SELECT
      'w' AS `type`,
      (
       IF(FIND_IN_SET(`w`.`id`, @global), 100, 0) +

       MATCH(`w`.`subject`)   AGAINST(@global) + MATCH(`w`.`subject`)   AGAINST(@global IN BOOLEAN MODE) +
       MATCH(`a`.`name`)      AGAINST(@global) + MATCH(`a`.`name`)      AGAINST(@global IN BOOLEAN MODE) +
       MATCH(`h`.`quotefile`) AGAINST(@global) + MATCH(`h`.`quotefile`) AGAINST(@global IN BOOLEAN MODE) +
       MATCH(`n`.`note`)      AGAINST(@global) + MATCH(`n`.`note`)      AGAINST(@global IN BOOLEAN MODE) +

       `u`.`match` + `u`.`bool` + 

       MATCH(`c`.`name`)      AGAINST(@global) + MATCH(`c`.`name`)      AGAINST(@global IN BOOLEAN MODE) + ( MATCH(`c`.`name`) AGAINST(@client) + MATCH(`c`.`name`) AGAINST(@client IN BOOLEAN MODE) ) * 10 +
       MATCH(`m`.`name`)      AGAINST(@global) + MATCH(`m`.`name`)      AGAINST(@global IN BOOLEAN MODE) + ( MATCH(`m`.`name`) AGAINST(@staff)  + MATCH(`m`.`name`) AGAINST(@staff IN BOOLEAN MODE)  ) * 10 +
       0
      ) AS `relevance`,

      `w`.`id` AS `wid`,
      GROUP_CONCAT(DISTINCT CONCAT(`a`.`id`, ':', `a`.`update_id`)) AS `aids`,
      GROUP_CONCAT(DISTINCT `h`.`id`) AS `hids`,
      GROUP_CONCAT(DISTINCT `n`.`id`) AS `nids`,
      GROUP_CONCAT(DISTINCT `u`.`id`) AS `uids`,

      MATCH(`w`.`subject`)   AGAINST(@global) + MATCH(`w`.`subject`)   AGAINST(@global IN BOOLEAN MODE) AS `w`,
      MATCH(`a`.`name`)      AGAINST(@global) + MATCH(`a`.`name`)      AGAINST(@global IN BOOLEAN MODE) AS `a`,
      MATCH(`h`.`quotefile`) AGAINST(@global) + MATCH(`h`.`quotefile`) AGAINST(@global IN BOOLEAN MODE) AS `h`,
      MATCH(`n`.`note`)      AGAINST(@global) + MATCH(`n`.`note`)      AGAINST(@global IN BOOLEAN MODE) AS `n`,
      `u`.`match` + `u`.`bool` AS `u`,

      MATCH(`c`.`name`)      AGAINST(@global) + MATCH(`c`.`name`)      AGAINST(@global IN BOOLEAN MODE) + ( MATCH(`c`.`name`)    AGAINST(@client) + MATCH(`c`.`name`)      AGAINST(@client IN BOOLEAN MODE) ) * 10 AS `c`,
      MATCH(`m`.`name`)      AGAINST(@global) + MATCH(`m`.`name`)      AGAINST(@global IN BOOLEAN MODE) + ( MATCH(`m`.`name`)    AGAINST(@staff)  + MATCH(`m`.`name`)      AGAINST(@staff IN BOOLEAN MODE)  ) * 10 AS `m`

    FROM `work` AS `w`
      LEFT JOIN `work_subscribers`  AS `s` ON `s`.`work_id` = `w`.`id`
      LEFT JOIN `work_files`        AS `a` ON `a`.`work_id` = `w`.`id`    AND ( MATCH(`a`.`name`)      AGAINST(@global IN BOOLEAN MODE) ) AND @attached > 0
      LEFT JOIN `work_cost_history` AS `h` ON `h`.`work_id` = `w`.`id`    AND ( MATCH(`h`.`quotefile`) AGAINST(@global IN BOOLEAN MODE) )
      LEFT JOIN `work_notes`        AS `n` ON `n`.`work_id` = `w`.`id`    AND ( MATCH(`n`.`note`)      AGAINST(@global IN BOOLEAN MODE) )
      LEFT JOIN (
                 SELECT
                     `su`.`id`,
                     `su`.`work_id`,
                     `su`.`date`,
                     MATCH(`su`.`text`) AGAINST(@global) AS `match`,
                     MATCH(`su`.`text`) AGAINST(@global IN BOOLEAN MODE) AS `bool`
                   FROM `work_updates` AS `su`
                   WHERE 
                     MATCH(`su`.`text`) AGAINST(@global IN BOOLEAN MODE)
                ) AS `u` ON `u`.`work_id` = `w`.`id`
      LEFT JOIN `clients`           AS `c` ON `c`.`id` = `w`.`client_id`
      LEFT JOIN `staff`             AS `m` ON `m`.`id` = `w`.`staff_id` OR `m`.`id` = `s`.`staff_id`

    WHERE
      TRUE
      AND (
            FIND_IN_SET(`w`.`status`, @tstatus)
        OR (@tstatus = -100 AND `w`.`staff_id` = 0)
           )
      AND (
           @staff = ''
        OR (@staff = '' AND (MATCH(`m`.`name`) AGAINST(@global IN BOOLEAN MODE)))
        OR MATCH(`m`.`name`) AGAINST(@staff IN BOOLEAN MODE)
           )
      AND (
           @client = ''
        OR (@client = '' AND (MATCH(`c`.`name`) AGAINST(@global IN BOOLEAN MODE)))
        OR MATCH(`c`.`name`) AGAINST(@client IN BOOLEAN MODE)
           )
      AND (
           @before = ''
        OR `w`.`date_created` < @before
        OR `n`.`date` < @before
        OR `u`.`date` < @before
           )
      AND (
           @after = ''
        OR `w`.`date_created` > @after
        OR `n`.`date` > @after
        OR `u`.`date` > @after
           )
      AND (
           `w`.`id` IN (@global)
        OR @client != ''
        OR @staff != ''

        OR MATCH(`w`.`subject`)   AGAINST(@global IN BOOLEAN MODE)
        OR MATCH(`a`.`name`)      AGAINST(@global IN BOOLEAN MODE)
        OR MATCH(`h`.`quotefile`) AGAINST(@global IN BOOLEAN MODE)
        OR MATCH(`n`.`note`)      AGAINST(@global IN BOOLEAN MODE)
        OR `u`.`id` IS NOT NULL
           )

    GROUP BY `w`.`id`
)

-- Global ordering and limitation.
ORDER BY `relevance` DESC
LIMIT 30
;