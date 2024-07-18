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

function serve_from_latest_snapshot() {
    $lsnapshots = array_map('basename', glob('/srv/porthos/webroot/d20*'));
    if (count($lsnapshots) == 0) {
        return 'not-found'; // Nginx will fail the file and return 404 for us
    }
    sort($lsnapshots);
    $snapshot = array_pop($lsnapshots);
    return $snapshot;
}

function serve_from_snapshots() {
    $lsnapshots = array_map('basename', glob('/srv/porthos/webroot/d20*'));
    if (count($lsnapshots) == 0) {
        return 'not-found'; // Nginx will not find the file and return 404 for us
    }
    sort($lsnapshots);
    $snapshot = array_pop($lsnapshots);
    // Minimum age (days) expected by tiers
    $tier_age = [3, 4, 5];
    while($snapshot != NULL) {
        $tier_id = system_tier($_SERVER['PHP_AUTH_USER']);
        if (snapshot_age($snapshot) >= $tier_age[$tier_id]) {
            break;
        }
        $snapshot = array_pop($lsnapshots);
    }
    return $snapshot;
}

function main() {
    $repo_view = isset($_SERVER['HTTP_X_REPO_VIEW']) ? $_SERVER['HTTP_X_REPO_VIEW'] : "unknown";
    $username = isset($_SERVER['PHP_AUTH_USER']) ? $_SERVER['PHP_AUTH_USER'] : "";
    $password = isset($_SERVER['PHP_AUTH_PW']) ? $_SERVER['PHP_AUTH_PW'] : "";

    $is_authenticated = ($username != "") && ($password != "");
    $is_distfeed_request = substr($_SERVER['DOCUMENT_URI'], 0, 10) == "/distfeed/";

    //
    // This is the enumeration if input => output cases
    //
    // AX, AM => SS
    // UX => LL
    // AL, UL, UM => HL
    //
    // Where A=Authenticated, U=Not authenticated,
    //       X=no-view, M=managed view, L=latest view
    //       SS=from snapshots, LL=from latest,
    //       HL=distfeed from head, other content from latest
    //

    if($repo_view == "unknown") {
        // Core <2.10 does not send the X-Repo-View header. We implement
        // the initial update policy for backward compatibility.
        if($is_authenticated) {
            $prefix = serve_from_snapshots(); // AX => SS
        } else {
            $prefix = serve_from_latest_snapshot(); // UX => LL
        }
    } else if($is_authenticated && $repo_view == "managed") {
        // Automated nightly update job receive managed updates.
        $prefix = serve_from_snapshots(); // AM => SS
    } else if($is_distfeed_request) {
        $prefix = 'head'; // AL, UL, UM => H.
    } else {
        // AL, UL, UM => .L
        $prefix = serve_from_latest_snapshot();
    }

    header('Cache-Control: private');
    header('X-Accel-Redirect: /' . $prefix . $_SERVER['DOCUMENT_URI']);
}

// Run
main();
