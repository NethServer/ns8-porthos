# ns8-porthos

Host Distfeed and Rocky Linux repository mirrors on Porthos

This module provides a simple web stack to serve DNF repositories and NS8
application Distfeed, based on Nginx + PHP-FPM.

## Install

Instantiate the module with:

    add-module ghcr.io/nethserver/porthos:latest 1

The output of the command will return the instance name.
Output example:

    {"module_id": "porthos1", "image_name": "porthos", "image_url": "ghcr.io/nethserver/porthos:latest"}

For optimal performance, mount a filesystem with data deduplication or a
LVM-VDO device. For example:

    dnf install lvm2 vdo vdo-support
    vgcreate porthos /dev/disk/by-id/scsi-porthos-volume
    lvcreate --type vdo --name webroot --extents '100%FREE' porthos
    mkfs.xfs -K /dev/porthos/webroot
    mkdir -vp /srv/porthos/webroot
    mount /dev/porthos/webroot /srv/porthos/webroot
    chown -c porthos1:porthos1 /srv/porthos/webroot

Create the `webroot` volume bounded to the device mount point:

    runagent -m porthos1 podman volume create --opt=device=/srv/porthos/webroot/ --opt=type=bind webroot

Then proceed with the first module configuration: see how to run
`configure-module` in the next section.

## Configure

See the current module setup:

    api-cli run module/porthos2/get-configuration

Output

```json
{
    "source": "rsync://mirror1.hs-esslingen.de",
    "retention": 45,
    "server_name": "rl1.dp.nethserver.net"
}
```

Change one or more attributes with a command like this:

    api-cli run module/porthos2/configure-module --data '{"retention":30}'

To publish the repository, a HTTP host name route must be configured from
the cluster-admin Settings page.

When the `configure-module` action is executed for the first time, service
and timer units are enabled and started.

Timers are:

- `take-snapshot.timer` is a weekly job that update Rocky Linux repository
  mirror contents and makes a copy of repodata.json and other metadata
  from NS8 repositories.

- `sync-head.timer` is a frequent job that 4 times per hour, from Monday to
  Friday and during working hours, makes a copy of repodata.json and other
  metadata from NS8 repositories.

Services are:

- `fpm.service`
- `nginx.service`

## Environment variables

- `PORTHOS_RETENTION`, number of snapshots preserved under `/srv/porthos/webroot`
- `PORTHOS_SOURCE`, base `rsync://` URL to a Rocky Linux official mirror
- `PORTHOS_SERVER_NAME`, name of virtual HTTP server; by default the node FQDN is set

## Containers

### fpm (PHP-FPM)

PHP scripts are installed under the `script/` directory. It is mounted in the
`fpm` container for execution. Changes to the contents of the `script/`
directory are immediately applied.

To locally override the FPM configuration file, create and edit a
`state/fpm.conf` file. Then, append to the `state/environment` file a line
like this:

    PORTHOS_FPM_PODMAN_ARGS=--volume=./fpm.conf:/srv/porthos/etc/fpm.conf:z

### nginx

The Nginx configuration is expanded from the template
`templates/nginx.conf` at `nginx` container startup. A limited set of
environment variables is substituted. Refer to Systemd `nginx.service`
unit definition for the template implementation.

## Tuning

Increase kernel network throughput. Sysctl settings:

```
net.ipv4.tcp_mem = 42456 169824 679296
net.core.wmem_max = 16482304
net.core.rmem_max = 16482304
net.ipv4.tcp_rmem = 4096 16384 16482304
```

## Content views

Content views are designed for two different purposes. On one hand, a
subscribed cluster wants to see the latest app updates from the Software
Center page, which needs the Distfeed content. On the other hand the
nightly cluster update procedure wants to install managed updates
automatically for both the base Rocky Linux OS and NS8 applications.

Web clients can send an optional `view` querystring parameter, with value
`latest` or `managed`. Any other value is considered like `latest`, but
this behavior may change in the future.

Header codes:

- `A` Authenticated
- `U` Anonymous
- `M` Managed repo view
- `L` Latest repo view
- `X` querystring `view` parameter not present

Request types:

- `df` request for Distfeed (like `repodata.json`)
- `rl` request for rockylinux mirror content

Response types:

- `L` content from the latest snapshot
- `S` content from a managed (past) snapshot
- `H` content from Distfeed head (updated multiple times per day from
  Distfeed upstream)

The following table summarizes the response for every headers/request
combination.

| headers/request | df | rl |
|-----------------|----|----|
| AX              | S  | S  |
| AM              | S  | S  |
| AL              | H  | L  |
| UM              | H  | L  |
| UL              | H  | L  |
| UX              | L  | L  |

## Content schedule

NS8 clients run automatic updates from Tuesday to Friday, at some random
time between 00:00 and 06:00 (client local time). Clients are assigned to
a content tier, based on a hash function of the credentials used for
authentication. Tiers have different, increasing size. The smaller one
receive updates before the larger one:

- Tier 1, 10%. Age 3 days
- Tier 2, 20%. Age 4 days
- Tier 3, 70%. Age 5 days

The tier Age defines how old a snapshot must be before being served by the
`managed` view.

The following table helps to understand the day of the week a snapshot is
served (values), starting from the day of the week a snapshot was created
(first column) and the client tier (first row). The table assumes a
snapshot is not created during the night (from 12 to 6 AM).

| -   | tier 1 | tier 2 | tier 3 |
|:---:|--------|--------|--------|
| FRI | Tue*   | Wed*   | Thu*   |
| SAT | Wed*   | Thu*   | Fri*   |
| SUN | Wed    | Thu    | Fri    |
| MON | Fri    | Tue*   | Tue*   |
| TUE | Tue*   | Tue*   | Tue*   |
| WED | Tue*   | Tue*   | Tue*   |
| THU | Tue*   | Tue*   | Wed*   |

The asterisk in a value indicates a day of the next week. The
`snapshot.timer` runs on Fridays at 21:00 UTC.

The table shows that taking a snapshot on Tuesdays and Wednesdays
flattenize the day of update for every tier, which may be undesired.


## Commands

The Distfeed head is synchoronized by the `sync-head` command. It fetches
Distfeed from its upstream on GitHub. A new snapshot of Rocky Linux and
Distfeed is created with `take-snapshot`. The two commands are described in
the next sections.

The two commands are executed periodically by two Systemd timer units:
`snapshot.timer` and `sync-head.timer`. They can be run manually at any
time too, but refer to the Content policy and Content schedule sections to
understand the implications.

### `take-snapshot`

To create a snapshot manually run:

    runagent -m porthos1 take-snapshot

As alternative start the equivalent Systemd service:

    runagent -m porthos1 systemctl --user start snapshot

Each snapshot contains a copy of NS8 Distfeed data fetched from GitHub and
an exact copy of Rocky Linux BaseOS and AppStream DNF repositories. To
save disk space and performance, it is recommended to store the snapshots
on a filesystem or block device that provides data deduplication.

### `sync-head`

To synchronize the copy of NS8 repodata with its GitHub upstream manually
run:

    runagent -m porthos1 sync-head

As alternative start the equivalent Systemd service:

    runagent -m porthos1 systemctl --user start sync-head

### Inspect the services status

Print the status of relevant Systemd units:

    runagent -m porthos1 systemctl --user status fpm.service nginx.service snapshot.timer sync-head.timer


## Testing

Test the module using the `test-module.sh` script:

    ./test-module.sh <NODE_ADDR> ghcr.io/nethserver/porthos:bug-7537

Additional arguments are forwarded to the `robot` command (see [Robot
Framework](https://robotframework.org/)).

For instance, to speed up testing on a local machine:

1. Skip the instance removal

       ./test-module.sh 10.5.4.1 ghcr.io/nethserver/porthos:bug-7537 --exclude remove

2. Continue to use the Porthos instance, skipping the installation steps.
   The `--variable` option is required to find the existing Porthos
   instance.

       ./test-module.sh 10.5.4.1 ghcr.io/nethserver/porthos:bug-7537 --exclude createORremove --variable MID:porthos1
