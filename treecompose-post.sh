#!/usr/bin/env bash

set -e

# Persistent journal by default, because Atomic doesn't have syslog
echo 'Storage=persistent' >> /etc/systemd/journald.conf

# See: https://bugzilla.redhat.com/show_bug.cgi?id=1051816
KEEPLANG=en_US
find /usr/share/locale -mindepth  1 -maxdepth 1 -type d -not -name "${KEEPLANG}" -exec rm -rf {} +
localedef --list-archive | grep -a -v ^"${KEEPLANG}" | xargs localedef --delete-from-archive
mv -f /usr/lib/locale/locale-archive /usr/lib/locale/locale-archive.tmpl
sed -i 's/EulerOS/EulerOS iSula/g' /etc/os-release
touch /etc/ostree/remotes.d/euleros-isula-host.conf
echo "[remote "euleros-isula-host"]" >> /etc/ostree/remotes.d/euleros-isula-host.conf
echo "url=http://35.185.171.199/ostree" >> /etc/ostree/remotes.d/euleros-isula-host.conf
echo "branches=euleros-isula-host/2/x86_64/standard" >> /etc/ostree/remotes.d/euleros-isula-host.conf
echo "gpg-verify=false" >> /etc/ostree/remotes.d/euleros-isula-host.conf
build-locale-archive
