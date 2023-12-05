# ns8-porthos

Repository mirror of base OS packages

## Install

Instantiate the module with:

    add-module ghcr.io/nethserver/porthos:latest 1

The output of the command will return the instance name.
Output example:

    {"module_id": "porthos1", "image_name": "porthos", "image_url": "ghcr.io/nethserver/porthos:latest"}

## Configure

TODO

## Testing

Test the module using the `test-module.sh` script:

    ./test-module.sh <NODE_ADDR> ghcr.io/nethserver/porthos:latest

The tests are made using [Robot Framework](https://robotframework.org/)
