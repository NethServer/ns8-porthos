<?php

/*
 * Copyright (C) 2023 Nethesis S.r.l.
 * SPDX-License-Identifier: GPL-3.0-or-later
 */

ini_set('date.timezone', 'UTC');
$DISTRO_VERSION = '9';

$repo = $_GET['repo'];
$arch  = $_GET['arch'];

$valid_repo_map = [
    'BaseOS-9' => ['BaseOS', $DISTRO_VERSION],
    'AppStream-9' => ['AppStream' => $DISTRO_VERSION],
];
$valid_arch_list = ['x86_64'];

if (!(in_array($repo, array_keys($valid_repo_map)) && in_array($arch, $valid_arch_list))) {
    http_response_code(404);
    exit(0);
}

$repo_dir = $valid_repo_map[$repo][0];
$version = $valid_repo_map[$repo][1];

header('Content-type: text/plain; charset=UTF-8');
echo "https://{$_SERVER['SERVER_NAME']}/rocky/{$version}/{$repo_dir}/{$arch}/os/\n";
