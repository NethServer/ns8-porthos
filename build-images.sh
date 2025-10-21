#!/bin/bash

#
# Copyright (C) 2023 Nethesis S.r.l.
# SPDX-License-Identifier: GPL-3.0-or-later
#

# Terminate on error
set -e

# Prepare variables for later use
images=()
# The image will be pushed to GitHub container registry
repobase="${REPOBASE:-ghcr.io/nethserver}"


#
# base for php fpm, required for the Redis precompiled module
#
reponame="porthos-fpm-base"
container="porthos-fpm-container"
if ! buildah inspect --type container "${container}" &>/dev/null; then
    container=$(buildah from --name "${container}" docker.io/library/debian:12.12-slim)
    buildah run "${container}" -- sh <<'EOF'
set -e
apt-get update
apt-get -y install php-fpm php-redis
apt-get clean
mkdir -vp /srv/porthos/webroot
chown -c -R www-data:www-data /srv/porthos/webroot
ln -v -s /usr/sbin/php-fpm* /usr/local/sbin/php-fpm
php --version
echo $(php -m)
php-fpm --version
EOF
    buildah commit "${container}" "${repobase}/${reponame}"
fi

#
# php-fpm -- Using Debian for precompiled Redis extension
#
echo "Building the FPM image..."
reponame="porthos-fpm"
container=$(buildah from ${repobase}/porthos-fpm-base)
buildah add "${container}" fpm /
buildah config \
    --volume=/srv/porthos/webroot \
    --entrypoint='["php-fpm", "-F", "-O", "-y", "/srv/porthos/etc/fpm.conf"]' \
    --cmd='' \
    "${container}"
# Commit the image
buildah commit "${container}" "${repobase}/${reponame}"

# Append the image URL to the images array
images+=("${repobase}/${reponame}")

#
# module image
#
echo "Building the module image..."
# Configure the image name
reponame="porthos"

# Create a new empty container image
container=$(buildah from scratch)

# Add imageroot directory to the container image
buildah add "${container}" imageroot /imageroot
buildah add "${container}" ui /ui
# Setup the entrypoint, ask to reserve one TCP port with the label and set a rootless container
buildah config --entrypoint=/ \
    --label="org.nethserver.tcp-ports-demand=3" \
    --label="org.nethserver.images=$(printf "%s:${IMAGETAG:-latest} " "${images[@]}") docker.io/library/nginx:1.29.2-alpine" \
    "${container}"
# Commit the image
buildah commit "${container}" "${repobase}/${reponame}"

# Append the image URL to the images array
images+=("${repobase}/${reponame}")

#
# NOTICE:
#
# It is possible to build and publish multiple images.
#
# 1. create another buildah container
# 2. add things to it and commit it
# 3. append the image url to the images array
#

#
# Setup CI when pushing to Github. 
# Warning! docker::// protocol expects lowercase letters (,,)
if [[ -n "${CI}" ]]; then
    # Set output value for Github Actions
    printf "images=%s\n" "${images[*],,}" >> "${GITHUB_OUTPUT}"
else
    # Just print info for manual push
    printf "Publish the images with:\n\n"
    for image in "${images[@],,}"; do printf "  buildah push %s docker://%s:%s\n" "${image}" "${image}" "${IMAGETAG:-latest}" ; done
    printf "\n"
fi
