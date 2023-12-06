# ns8-porthos

Host Rocky Linux repository mirrors on Porthos

This module provides a simple web stack for DNF repositories, based on Nginx + PHP-FPM

## Install

Instantiate the module with:

    add-module ghcr.io/nethserver/porthos:latest 1

The output of the command will return the instance name.
Output example:

    {"module_id": "porthos1", "image_name": "porthos", "image_url": "ghcr.io/nethserver/porthos:latest"}

For optimal performance, mount a filesystem with data deduplication or a
LVM-VDO device. For example:

    dnf install lvm2 vdo vdo-support
    vgcreate porthos /dev/sda
    lvcreate --type vdo --name webroot --extents 8191 porthos
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

## Commands

### `take-snapshot`

To create a snapshot manually run:

    runagent -m porthos1 take-snapshot

As alternative start the equivalent Systemd service:

    runagent -m porthos1 systemctl --user start snapshot

### Inspect the services status

Print the status of relevant Systemd units:

    runagent -m porthos1 systemctl --user status fpm.service nginx.service snapshot.timer

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
