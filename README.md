# Professional Development Environment Setup
### `setup_dev_env.sh` — Debian 12 (Bookworm) | OpenSUSE Tumbleweed

> **Tumbleweed status:** The script includes full OpenSUSE Tumbleweed support but
> this has not yet been tested. Debian 12 is the actively tested and verified platform.
> Tumbleweed testing is planned — use with caution on that platform until confirmed.

---

## What This Script Does

`setup_dev_env.sh` is a fully automated, unattended development environment installer
that sets up a complete professional C/C++, embedded, web, and scripting toolchain on
a fresh Debian 12 or OpenSUSE Tumbleweed installation. It must be run as root:

```bash
sudo bash setup_dev_env.sh
```

It is safe to re-run. All steps check whether components are already installed or
configured before doing anything, so running it a second time will not cause
duplicate entries, broken packages, or overwritten configuration.

---

## Steps Performed

| Step | What it does |
|------|-------------|
| **0** | Fixes broken dependencies, unholds held packages, pins libcurl4 to Bookworm, deduplicates apt sources, removes legacy repo files from previous runs |
| **1** | Full system update and upgrade (`apt-get update && dist-upgrade`) |
| **2** | Enables i386 (32-bit) architecture support |
| **3** | Installs `build-essential` core toolchain (gcc, g++, make, binutils) |
| **4** | Core dev tools: cmake, ninja, clang, lld, lldb, gdb, valgrind, strace, ltrace, meson, ccache, git, git-lfs, git-flow |
| **5** | Documentation and analysis: doxygen, graphviz, plantuml, cppcheck, bear, iwyu, shellcheck, pandoc |
| **6** | Hardware/embedded libraries: libgpiod, libi2c, libmodbus, libssl, libcurl, libudev, libusb, CAN bus, MQTT (mosquitto) |
| **7** | MariaDB: server, client, backup, C dev library, ODBC driver, Perl and Python connectors — hardened automatically |
| **8** | GTK 2/3/4 + full gtkmm C++ wrappers (sigc++, cairomm, pangomm) + GObject introspection + D-Bus |
| **9** | Python 3 full stack via apt (`python3-*` packages) + pip installs for packages not in Debian repos |
| **10** | Docker CE (from Docker's official repo) + Podman + buildah + skopeo |
| **11** | Cross-compilation: Raspberry Pi armhf (32-bit) and aarch64 (64-bit), AVR (gcc-avr, avrdude, gdb-avr), SDCC (PIC/STM8/MCS51/Z80), QEMU ARM |
| **12** | Network/IPC libraries: ZeroMQ, Boost, Protobuf, WebSockets, libmicrohttpd, nlohmann JSON, rapidjson |
| **13** | Database extras: SQLite3, PostgreSQL client libs, Redis + hiredis C client |
| **14** | Testing and quality: Google Test + gmock (built from source), lcov, gcovr, clang-analyzer (scan-build) |
| **15** | Node.js 22.x LTS via NodeSource official repo + global npm tools |
| **16** | PHP 8.3 via Sury official repo + full extension set + FPM (Composer installed separately — see below) |
| **17** | Perl 5 + DBI/DBD modules (MySQL, SQLite, PostgreSQL) + JSON/XML/YAML + cpanm |
| **18** | JSON tools: jq, nlohmann, rapidjson, jansson, cJSON, json-c, fx, ajv-cli |
| **19** | Networking tools: nmap, mtr, tcpdump, tshark, telnet, ftp, iperf3, socat, httpie, SNMP, and more |
| **20** | OpenSSH server + rsync |

---

## Post-Install Actions Required

### MariaDB — Set Root Password

The installer hardens MariaDB automatically (removes anonymous users, test database,
remote root access) but does **not** set a root password. Do this immediately after
the script completes:

```bash
sudo mysql_secure_installation
```

Follow the prompts — set a strong root password and accept all the hardening options.

---

### Docker — Add Your User to the docker Group

The Docker daemon requires group membership to use without sudo:

```bash
sudo usermod -aG docker $USER
newgrp docker
# or log out and back in for the change to take full effect
```

Verify it works:
```bash
docker run hello-world
```

---

### Python — Isolated Project Environments

Debian 12 enforces PEP 668 which blocks system-wide `pip install` by default.
The script installs a helper wrapper for the rare cases you need a system-wide install:

```bash
# For isolated project work (recommended)
python3 -m venv ~/.venvs/myproject
source ~/.venvs/myproject/bin/activate
pip install <package>

# For system-wide installs (use sparingly)
pip3-system <package>
# equivalent to: pip3 install --break-system-packages <package>
```

Packages not available in Debian 12 apt repos and installed via pip:
- `autopep8`
- `isort`
- `jsonpath-ng`

---

### PHP — Composer

Composer was **not** installed automatically because its installer makes network
calls that can hang indefinitely in an unattended script context.

Install it manually when ready — it takes about 10 seconds:

```bash
# Step 1 -- Download the installer
curl -fsSL https://getcomposer.org/installer -o /tmp/composer-setup.php

# Step 2 -- Verify the checksum (important -- do not skip)
EXPECTED=$(curl -fsSL https://composer.github.io/installer.sig)
ACTUAL=$(php -r "echo hash_file('sha384', '/tmp/composer-setup.php');")
echo "Expected : $EXPECTED"
echo "Actual   : $ACTUAL"
# Both lines must match before proceeding

# Step 3 -- Install globally
sudo php /tmp/composer-setup.php \
    --install-dir=/usr/local/bin \
    --filename=composer \
    --2
rm /tmp/composer-setup.php

# Step 4 -- Verify
composer --version

# Keep it updated
sudo composer self-update
```

**Daily Composer usage:**
```bash
composer require vendor/package      # add a dependency
composer install                     # install from composer.json
composer update                      # update all dependencies
composer dump-autoload               # rebuild the autoloader
```

Full documentation: https://getcomposer.org/doc/

---

### Perl — Installing Additional Modules

The script installs core Perl modules via apt. For anything beyond that use `cpanm`:

```bash
cpanm Module::Name
# Example:
cpanm DateTime
cpanm LWP::UserAgent
cpanm DBD::MariaDB
```

---

### SSH — Harden the Server

The script installs and enables OpenSSH server but leaves the default configuration
in place. For a development machine that may be accessed remotely, harden it:

```bash
sudo nano /etc/ssh/sshd_config
```

Recommended changes:
```
PasswordAuthentication no       # use SSH keys only
PermitRootLogin no              # never log in as root over SSH
PubkeyAuthentication yes
AuthorizedKeysFile .ssh/authorized_keys
```

Then restart the service:
```bash
sudo systemctl restart ssh
```

---

### Cross-Compilation Quick Reference

**Raspberry Pi — 32-bit (Pi 1 / 2 / 3 / Zero):**
```bash
arm-linux-gnueabihf-gcc-12 -o hello hello.c
arm-linux-gnueabihf-g++-12 -o hello hello.cpp
```

**Raspberry Pi — 64-bit (Pi 4 / Pi 5):**
```bash
aarch64-linux-gnu-gcc-12 -o hello hello.c
aarch64-linux-gnu-g++-12 -o hello hello.cpp
```

**Run ARM binaries on the dev machine (QEMU):**
```bash
qemu-arm-static ./hello          # 32-bit
qemu-aarch64-static ./hello      # 64-bit
```

**AVR (Arduino / ATmega):**
```bash
# Compile
avr-gcc -mmcu=atmega328p -Os -o hello.elf hello.c
# Convert to hex
avr-objcopy -O ihex hello.elf hello.hex
# Flash to board (adjust port as needed)
avrdude -c arduino -p m328p -P /dev/ttyUSB0 -b 115200 -U flash:w:hello.hex
# Note: g++-avr does not exist as a separate package --
# C++ support is bundled inside gcc-avr. Use avr-g++ directly.
```

**SDCC — Small Device C Compiler (PIC / STM8 / MCS51 / Z80):**
```bash
# Intel MCS-51 / 8051
sdcc -mmcs51 hello.c
# STM8
sdcc -mstm8 hello.c
# Zilog Z80
sdcc -mz80 hello.c
# PIC (requires gputils)
sdcc -mpic16 -p18f4550 hello.c
```

---

### iperf3 — On-Demand Bandwidth Testing

During installation, iperf3 asks whether to run as a permanent background daemon.
**The correct answer is No** for a development machine — you do not need port 5201
permanently open. Use it on demand instead:

```bash
# On the machine you want to test (server mode)
iperf3 -s
# Press Ctrl+C when done

# On the other machine (client mode)
iperf3 -c <server-ip>

# With options
iperf3 -c <server-ip> -t 30 -P 4     # 30 second test, 4 parallel streams
iperf3 -c <server-ip> -R              # reverse (test download speed)
```

If you later decide you want it as a daemon:
```bash
sudo systemctl enable --now iperf3
```

---

## Step 15 — Node.js npm Deprecation Warnings

When Step 15 installs the global npm packages you will see warnings like these:

```
npm warn deprecated inflight@1.0.6: This module is not supported...
npm warn deprecated glob@7.2.3: Old versions of glob are not supported...
npm warn deprecated whatwg-encoding@2.0.0: Use @exodus/bytes instead...
npm warn deprecated glob@10.5.0: Old versions of glob are not supported...
```

**These are not errors and do not require any action.**

What they mean: the tools you installed (jest, eslint, prettier, etc.) depend on
other packages internally. Some of those internal packages are older versions that
npm considers deprecated. The warnings are about those *internal* dependencies,
not about the tools themselves.

The tools (TypeScript, ESLint, Jest, PM2, Nodemon etc.) all install and work
correctly. The warnings are cosmetic output from npm's dependency resolver.

If you want to check the health of your global packages at any time:
```bash
# Check for outdated global packages
ncu -g

# See which packages need funding
npm fund

# List all installed global packages
npm list -g --depth=0
```

Node.js and npm versions installed:
```bash
node --version    # v22.x.x
npm --version     # 11.x.x
```

---

## Known Issues & Notes

**libcurl4 version conflict** — On a Debian 12 system where third-party repos
(PHP Sury, Docker) have been added, `libcurl4` can get upgraded to a Trixie
backport version (`~bpo13`) which breaks `libcurl4-openssl-dev`. Step 0 detects
and pins this automatically. If you ever see curl-related dependency errors,
run Step 0 manually:
```bash
sudo bash -c 'source setup_dev_env.sh; detect_distro; step0_fix_dependencies'
```

**SNMP MIBs** — `snmp-mibs-downloader` requires the `non-free` component of the
Debian repos. The script enables this in-place in `/etc/apt/sources.list`.
Test that MIBs are working after install:
```bash
snmptranslate -m all -IR sysDescr.0
```

**simulavr** — The AVR simulator was removed from Debian 12 repositories.
As an alternative, `simavr` can be built from source:
```bash
git clone https://github.com/buserror/simavr.git
cd simavr && make
```

**Python 2** — Python 2 is not available in official Debian 12 repositories.
If you need it, use `pyenv`:
```bash
curl https://pyenv.run | bash
pyenv install 2.7.18
pyenv global 2.7.18
```

**Composer** — Not auto-installed due to network timeout issues in unattended
mode. See the Composer section above for the manual install procedure.

---

## Updating Installed Tools

```bash
# System packages
sudo apt-get update && sudo apt-get upgrade

# Global npm packages
ncu -g                          # see what's outdated
sudo npm update -g              # update all

# PHP Composer (once installed)
sudo composer self-update

# Perl modules via cpanm
cpanm --self-upgrade

# Python packages (system-wide)
pip3-system --upgrade <package>

# Docker
sudo apt-get install --only-upgrade docker-ce

# Node.js (to upgrade to a new major version)
# Edit NODE_MAJOR at the top of setup_dev_env.sh and re-run Step 15
```

---

## File Locations

| File | Purpose |
|------|---------|
| `/usr/local/bin/pip3-system` | pip wrapper for system-wide Python installs |
| `/usr/local/bin/composer` | Composer (once manually installed) |
| `/usr/local/bin/arm-linux-gnueabihf-gcc` | RPi 32-bit cross-compiler symlink |
| `/usr/local/bin/aarch64-linux-gnu-gcc` | RPi 64-bit cross-compiler symlink |
| `/etc/apt/sources.list.d/docker.list` | Docker CE apt repo |
| `/etc/apt/sources.list.d/nodesource.list` | NodeSource apt repo |
| `/etc/apt/sources.list.d/php-sury.list` | PHP 8.3 Sury apt repo |
| `/etc/apt/preferences.d/pin-libcurl` | libcurl4 Bookworm version pin |
| `/root/COMPOSER_INSTALL.md` | Composer install instructions (written by script) |

---

*Script version 2.0.0 — Debian 12 tested and verified.*
*OpenSUSE Tumbleweed support included but not yet tested.*
# FullstackDevloperScriptDebian12
