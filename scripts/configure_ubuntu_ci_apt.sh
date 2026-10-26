#!/bin/sh
set -eu
# GitHub's Ubuntu image resolves its mirror through this file, not just ubuntu.sources.
test -f /etc/apt/sources.list.d/ubuntu.sources
printf 'https://archive.ubuntu.com/ubuntu/\n' > /etc/apt/apt-mirrors.txt
sed -i 's@http://azure\.archive\.ubuntu\.com@https://archive.ubuntu.com@g;s@http://archive\.ubuntu\.com@https://archive.ubuntu.com@g;s@http://security\.ubuntu\.com@https://security.ubuntu.com@g' /etc/apt/sources.list.d/ubuntu.sources
printf 'Acquire::http::Timeout "30";\nAcquire::https::Timeout "30";\nAcquire::Retries "2";\n' > /etc/apt/apt.conf.d/99dls-ci-network
