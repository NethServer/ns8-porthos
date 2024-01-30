<?php

/*
 * Copyright (C) 2023 Nethesis S.r.l.
 * SPDX-License-Identifier: GPL-3.0-or-later
 */

ini_set('date.timezone', 'UTC');

// Disable the Content-Type header in PHP, so that nginx x-accel can add its own
ini_set('default_mimetype', FALSE);

// Return the 0-based tier id for the given $system_id
function system_tier($system_id) {
    $idx = abs(crc32($system_id)) % 100;
    if($idx < 10) {
        $tier_id = 0;
    } elseif($idx < 30) {
        $tier_id = 1;
    } else {
        $tier_id = 2;
    }
    return $tier_id;
}

// Return the age (days) of the given $snapshot
function snapshot_age($snapshot) {
    $year = substr($snapshot, 1, 4);
    $month = substr($snapshot, 5, 2);
    $day = substr($snapshot, 7, 2);
    $hour = substr($snapshot, 10, 2);
    $minute = substr($snapshot, 12, 2);
    $second = substr($snapshot, 14, 2);
    $frac = substr($snapshot, 16, 2);

    $dt_current = new DateTime();
    $dt_snapshot = new DateTime("$year-$month-$day $hour:$minute:$second.$frac");

    // Calculate the difference in days between the two dates
    $dt_interval = $dt_current->diff($dt_snapshot);

    $days_age = $dt_interval->format('%a');
    return $days_age;
}

function main() {
    // Minimum age (days) expected by tiers
    $tier_age = [3, 4, 5];

    $lsnapshots = array_map('basename', glob('/srv/porthos/webroot/d20*'));

    if (count($lsnapshots) == 0) {
        http_response_code(404);
        echo "Not found\n";
    }

    $username = isset($_SERVER['PHP_AUTH_USER']) ? $_SERVER['PHP_AUTH_USER'] : "";
    $password = isset($_SERVER['PHP_AUTH_PW']) ? $_SERVER['PHP_AUTH_PW'] : "";

    sort($lsnapshots);

    $snapshot = array_pop($lsnapshots);
    if($username && $password) {
        // Authenticated clients gain access to older tiers
        while($snapshot != NULL) {
            $tier_id = system_tier($username);
            if (snapshot_age($snapshot) > $tier_age[$tier_id]) {
                break;
            }
            $snapshot = array_pop($lsnapshots);
        }
    }

    header('Cache-Control: private');
    header('X-Accel-Redirect: /' . $snapshot . $_SERVER['DOCUMENT_URI']);
}

// Run
main();
