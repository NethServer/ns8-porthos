<?php

/*
 * Copyright (C) 2023 Nethesis S.r.l.
 * SPDX-License-Identifier: GPL-3.0-or-later
 */

ini_set('date.timezone', 'UTC');

$uri = $_SERVER['DOCUMENT_URI']; // XXX parse URI

print_r(parse_url($uri));
print_r($_GET);