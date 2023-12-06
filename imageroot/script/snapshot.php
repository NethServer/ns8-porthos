<?php

/*
 * Copyright (C) 2023 Nethesis S.r.l.
 * SPDX-License-Identifier: GPL-3.0-or-later
 */

ini_set('date.timezone', 'UTC');

$uri = $_SERVER['DOCUMENT_URI']; // XXX parse URI

// Disable the Content-Type header in PHP, so that nginx x-accel can add its own
ini_set('default_mimetype', FALSE);

$snapshots = array_map('basename', glob('/srv/porthos/webroot/d20*'));

if (count($snapshots) > 0) {
    sort($snapshots);
    header('Cache-Control: private');
    header('X-Accel-Redirect: /' . end($snapshots) . $uri);
} else {
    http_response_code(404);
    echo "Not found\n";
}
