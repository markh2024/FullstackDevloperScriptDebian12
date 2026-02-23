#!/usr/bin/env bash
# =============================================================================
#  Professional Development Environment Setup
#  Supports : Debian 12 (Bookworm) | OpenSUSE Tumbleweed
#  Version  : 2.0.0
#  Usage    : sudo bash setup_dev_env.sh
# =============================================================================

set -euo pipefail
IFS=$'\n\t'

# ── Colours ───────────────────────────────────────────────────────────────────
RED='\033[0;31m'; GREEN='\033[0;32m'; YELLOW='\033[1;33m'
CYAN='\033[0;36m'; BOLD='\033[1m'; RESET='\033[0m'

log()    { echo -e "${GREEN}[INFO]${RESET}  $*"; }
warn()   { echo -e "${YELLOW}[WARN]${RESET}  $*"; }
error()  { echo -e "${RED}[ERROR]${RESET} $*" >&2; }
section(){ echo -e "\n${BOLD}${CYAN}══════════════════════════════════════════════════════${RESET}"; \
           echo -e "${BOLD}${CYAN}  $*${RESET}"; \
           echo -e "${BOLD}${CYAN}══════════════════════════════════════════════════════${RESET}\n"; }

# ── Configurable versions ─────────────────────────────────────────────────────
NODE_MAJOR=22          # NodeSource LTS major version (20 or 22)
PHP_VERSION=8.3        # Sury PHP version for Debian

# ── Prevent ANY interactive apt dialogs throughout the entire script ────────────
export DEBIAN_FRONTEND=noninteractive
export DEBCONF_NONINTERACTIVE_SEEN=true

# ── Root check ────────────────────────────────────────────────────────────────
if [[ $EUID -ne 0 ]]; then
    error "This script must be run as root (sudo bash $0)"
    exit 1
fi

# =============================================================================
#  DISTRO DETECTION
# =============================================================================
detect_distro() {
    [[ -f /etc/os-release ]] || { error "/etc/os-release not found."; exit 1; }
    source /etc/os-release
    DISTRO_ID="${ID,,}"
    DISTRO_NAME="${NAME}"
    DISTRO_VERSION="${VERSION_ID:-unknown}"
    DISTRO_CODENAME="${VERSION_CODENAME:-}"

    case "${DISTRO_ID}" in
        debian)
            [[ "${DISTRO_VERSION}" == "12" ]] || {
                warn "Detected Debian ${DISTRO_VERSION} -- script targets Debian 12 (Bookworm)."
                read -rp "Continue anyway? [y/N] " a; [[ "${a,,}" == "y" ]] || exit 1
            }
            DISTRO="debian"
            ;;
        opensuse-tumbleweed|opensuse*)
            [[ "${DISTRO_ID}" == "opensuse-tumbleweed" ]] || {
                warn "Detected ${DISTRO_NAME} -- script targets OpenSUSE Tumbleweed."
                read -rp "Continue anyway? [y/N] " a; [[ "${a,,}" == "y" ]] || exit 1
            }
            DISTRO="tumbleweed"
            ;;
        *)
            error "Unsupported: ${DISTRO_NAME} (${DISTRO_ID})"
            error "Supported: Debian 12 | OpenSUSE Tumbleweed"
            exit 1 ;;
    esac

    log "Detected: ${BOLD}${DISTRO_NAME} ${DISTRO_VERSION}${RESET}"
}

# ── Debian install helper ─────────────────────────────────────────────────────
deb_install() { apt-get install -y --no-install-recommends "$@"; }

# =============================================================================
#  STEP 0 -- FIX BROKEN DEPENDENCIES
# =============================================================================
step0_fix_dependencies() {
    section "STEP 0 -- Fix Broken Dependencies & Conflicts"
    case "${DISTRO}" in
        debian)
            log "Configuring any partially installed packages..."
            dpkg --configure -a

            log "Attempting to fix broken installs..."
            apt-get install -f -y

            log "Cleaning up obsolete packages..."
            apt-get autoremove -y
            apt-get autoclean -y

            log "Removing any held packages that could block installs..."
            # List held packages and offer to unhold them
            HELD=$(dpkg --get-selections | awk '/hold$/{print $1}')
            if [[ -n "${HELD}" ]]; then
                warn "The following packages are held and may cause conflicts:"
                echo "${HELD}"
                echo ""
                read -rp "Unhold all held packages so they can be upgraded? [Y/n] " ans
                if [[ "${ans,,}" != "n" ]]; then
                    echo "${HELD}" | xargs -r apt-mark unhold
                    log "Packages unheld."
                else
                    warn "Held packages left as-is -- conflicts may occur later."
                fi
            else
                log "No held packages found."
            fi

            # ── libcurl conflict fix ──────────────────────────────────────────
            # Detect if libcurl4 has been pulled from backports/third-party repo
            # (version string contains bpo or deb13) which breaks the Bookworm
            # dev packages. Pin and downgrade proactively if so.
            CURL_VER=$(dpkg-query -W -f='${Version}' libcurl4 2>/dev/null || true)
            if [[ "${CURL_VER}" == *"bpo"* || "${CURL_VER}" == *"deb13"* ]]; then
                warn "libcurl4 ${CURL_VER} is from a backport/external repo."
                warn "Pinning and downgrading to Bookworm version (7.88.1)..."
                cat > /etc/apt/preferences.d/pin-libcurl <<'PINEOF'
Package: libcurl4 libcurl4-openssl-dev libcurl4-gnutls-dev libcurl3-gnutls curl
Pin: release n=bookworm
Pin-Priority: 1001
PINEOF
                apt-get update -y
                apt-get install -y --allow-downgrades                     "libcurl4=7.88.1*"                     "curl=7.88.1*"                     || warn "Could not downgrade libcurl4 by exact version -- pin file still active."
                log "libcurl4 pinned to Bookworm. Conflict resolved."
            else
                # Apply the pin regardless as a preventive measure for later steps
                log "Applying preventive libcurl4 Bookworm pin..."
                cat > /etc/apt/preferences.d/pin-libcurl <<'PINEOF'
Package: libcurl4 libcurl4-openssl-dev libcurl4-gnutls-dev libcurl3-gnutls curl
Pin: release n=bookworm
Pin-Priority: 1001
PINEOF
                log "libcurl4 pin applied (preventive)."
            fi

            # ── Check for other common conflict patterns ───────────────────────
            log "Scanning for other known cross-release package conflicts..."

            # Any package from deb13/trixie/bpo on a Bookworm system is suspect
            FOREIGN=$(dpkg-query -W -f='${Package} ${Version}\n' 2>/dev/null \
                | awk '/deb13|~bpo13|trixie/{print $1}')
            if [[ -n "${FOREIGN}" ]]; then
                warn "The following packages appear to be from Trixie/backports:"
                echo "${FOREIGN}"
                warn "These may cause dependency conflicts. Consider pinning them."
                warn "A pin file template has been written to:"
                warn "  /etc/apt/preferences.d/pin-foreign-packages"
                # Write a template pin file for the user to review
                {
                    echo "# Auto-generated by setup_dev_env.sh"
                    echo "# Review and adjust as needed"
                    for PKG in ${FOREIGN}; do
                        echo ""
                        echo "Package: ${PKG}"
                        echo "Pin: release n=bookworm"
                        echo "Pin-Priority: 1001"
                    done
                } > /etc/apt/preferences.d/pin-foreign-packages
            else
                log "No foreign-release packages detected."
            fi

            # ── Remove legacy non-free.list if sources.list already has non-free ─
            # Handles the case where a previous script run created non-free.list
            # but sources.list already contained non-free, causing duplicates.
            if [[ -f /etc/apt/sources.list.d/non-free.list ]]; then
                if grep -qE "^deb.*non-free" /etc/apt/sources.list 2>/dev/null; then
                    log "Removing redundant non-free.list (sources.list already has non-free)..."
                    rm -f /etc/apt/sources.list.d/non-free.list
                fi
            fi

            # ── Deduplicate apt sources ───────────────────────────────────────
            # Scans sources.list and all files in sources.list.d/ and removes
            # any duplicate deb lines, keeping only the first occurrence.
            # Also removes any empty or comment-only .list files left behind.
            log "Scanning for duplicate apt sources..."

            SEEN_SOURCES=()
            DUPES_FOUND=0

            # Build list of all source files to check
            SOURCE_FILES=(/etc/apt/sources.list)
            while IFS= read -r -d '' f; do
                SOURCE_FILES+=("$f")
            done < <(find /etc/apt/sources.list.d/ -name "*.list" -print0 2>/dev/null)

            for FILE in "${SOURCE_FILES[@]}"; do
                [[ -f "${FILE}" ]] || continue
                CLEAN_LINES=()
                CHANGED=false
                while IFS= read -r line; do
                    # Only deduplicate active deb lines, pass comments/blanks through
                    if [[ "${line}" =~ ^deb[[:space:]] ]]; then
                        # Normalise whitespace for comparison
                        NORM=$(echo "${line}" | tr -s ' ')
                        if printf '%s
' "${SEEN_SOURCES[@]}" | grep -qxF "${NORM}" 2>/dev/null; then
                            warn "  Duplicate removed from ${FILE}: ${NORM}"
                            CHANGED=true
                            (( DUPES_FOUND++ )) || true
                        else
                            SEEN_SOURCES+=("${NORM}")
                            CLEAN_LINES+=("${line}")
                        fi
                    else
                        CLEAN_LINES+=("${line}")
                    fi
                done < "${FILE}"

                if [[ "${CHANGED}" == "true" ]]; then
                    printf '%s
' "${CLEAN_LINES[@]}" > "${FILE}"
                    log "  Cleaned: ${FILE}"
                fi
            done

            if [[ ${DUPES_FOUND} -eq 0 ]]; then
                log "No duplicate apt sources found."
            else
                log "${DUPES_FOUND} duplicate source line(s) removed."
            fi

            # ── Remove empty .list files in sources.list.d ────────────────────
            log "Checking for empty source files..."
            while IFS= read -r -d '' f; do
                # File is effectively empty if it has no active deb lines
                if ! grep -qE "^deb[[:space:]]" "${f}" 2>/dev/null; then
                    log "  Removing empty/inactive source file: ${f}"
                    rm -f "${f}"
                fi
            done < <(find /etc/apt/sources.list.d/ -name "*.list" -print0 2>/dev/null)

            # ── Final apt-get check ───────────────────────────────────────────
            log "Running final dependency check..."
            apt-get update -y
            apt-get install -f -y
            log "Dependency repair complete."
            ;;

        tumbleweed)
            log "Running zypper verify to check package integrity..."
            zypper --non-interactive verify || true

            log "Fixing broken dependencies..."
            zypper --non-interactive install -f --no-recommends                 $(zypper packages --broken 2>/dev/null                     | awk -F"|" '"'"'NR>4 && /^i/{print $3}'"'"'                     | tr -d '"'"' '"'"') 2>/dev/null                 || log "No broken packages to fix."

            log "Cleaning zypper cache..."
            zypper --non-interactive clean --all

            log "Refreshing all repos..."
            zypper --non-interactive refresh
            log "Dependency repair complete."
            ;;
    esac
}

# =============================================================================
#  STEP 1 -- SYSTEM UPDATE
# =============================================================================
step1_system_update() {
    section "STEP 1 -- System Update & Upgrade"
    case "${DISTRO}" in
        debian)
            apt-get update -y
            apt-get upgrade -y
            apt-get dist-upgrade -y
            apt-get autoremove -y
            apt-get autoclean -y
            ;;
        tumbleweed)
            zypper --non-interactive refresh
            zypper --non-interactive dist-upgrade --allow-vendor-change
            ;;
    esac
    log "System update complete."
}

# =============================================================================
#  STEP 2 -- ENABLE i386 ARCHITECTURE
# =============================================================================
step2_enable_i386() {
    section "STEP 2 -- Enable i386 (32-bit) Architecture"
    case "${DISTRO}" in
        debian)
            dpkg --print-foreign-architectures | grep -q i386 \
                && log "i386 already enabled." \
                || { dpkg --add-architecture i386; apt-get update -y; log "i386 enabled."; }
            ;;
        tumbleweed)
            zypper --non-interactive install -y \
                glibc-32bit glibc-devel-32bit libstdc++6-32bit \
                || warn "Some 32-bit packages unavailable -- continuing."
            ;;
    esac
}

# =============================================================================
#  STEP 3 -- BUILD ESSENTIAL
# =============================================================================
step3_build_essential() {
    section "STEP 3 -- Build Essential Toolchain"
    case "${DISTRO}" in
        debian)
            deb_install build-essential
            ;;
        tumbleweed)
            zypper --non-interactive install -y -t pattern devel_basis
            zypper --non-interactive install -y gcc gcc-c++ make binutils glibc-devel
            ;;
    esac
    log "Build essential installed."
}

# =============================================================================
#  STEP 4 -- CORE DEVELOPER TOOLS
# =============================================================================
step4_developer_tools() {
    section "STEP 4 -- Core Developer Tools"
    case "${DISTRO}" in
        debian)
            deb_install \
                cmake ninja-build pkg-config \
                git git-lfs git-flow \
                curl wget \
                gdb lldb \
                valgrind strace ltrace \
                clang clang-format clang-tidy clang-tools \
                lld \
                bison flex \
                autoconf automake libtool m4 \
                gettext meson ccache \
                patchelf elfutils binutils-dev
            ;;
        tumbleweed)
            zypper --non-interactive install -y \
                cmake ninja pkg-config \
                git git-lfs gitflow \
                curl wget \
                gdb lldb \
                valgrind strace ltrace \
                clang clang-tools \
                lld \
                bison flex \
                autoconf automake libtool m4 \
                gettext-tools meson ccache \
                patchelf elfutils binutils-devel
            ;;
    esac
    log "Core developer tools installed."
}

# =============================================================================
#  STEP 5 -- DOCUMENTATION & STATIC ANALYSIS
# =============================================================================
step5_doc_and_analysis() {
    section "STEP 5 -- Documentation & Static Analysis"
    case "${DISTRO}" in
        debian)
            deb_install \
                doxygen graphviz plantuml \
                cppcheck bear \
                iwyu \
                shellcheck \
                pandoc \
                man-db manpages-dev
            ;;
        tumbleweed)
            zypper --non-interactive install -y \
                doxygen graphviz plantuml \
                cppcheck bear \
                include-what-you-use \
                ShellCheck \
                pandoc \
                man man-pages
            ;;
    esac
    log "Documentation & analysis tools installed."
}

# =============================================================================
#  STEP 6 -- HARDWARE / EMBEDDED LIBRARIES
# =============================================================================
step6_hardware_libs() {
    section "STEP 6 -- Hardware / Embedded Interface Libraries"
    case "${DISTRO}" in
        debian)
            deb_install \
                libgpiod-dev gpiod \
                libi2c-dev i2c-tools \
                libmodbus-dev \
                libssl-dev \
                libcurl4-openssl-dev \
                libudev-dev \
                libusb-1.0-0-dev \
                libsocketcan-dev can-utils \
                libmosquitto-dev mosquitto mosquitto-clients
            ;;
        tumbleweed)
            zypper --non-interactive install -y \
                libgpiod-devel gpiod \
                i2c-tools-devel \
                libmodbus-devel \
                openssl-devel \
                libcurl-devel \
                libudev-devel \
                libusb-1_0-devel \
                libsocketcan-devel can-utils \
                libmosquitto-devel mosquitto mosquitto-clients
            ;;
    esac
    log "Hardware libraries installed."
}

# =============================================================================
#  STEP 7 -- MARIADB (Server + Client + ODBC + Connectors)
# =============================================================================
step7_mariadb() {
    section "STEP 7 -- MariaDB Professional Setup"
    case "${DISTRO}" in
        debian)
            deb_install \
                mariadb-server mariadb-client mariadb-backup \
                libmariadb-dev libmariadb-dev-compat libmariadb3 \
                mariadb-plugin-connect \
                unixodbc unixodbc-dev odbc-mariadb \
                libdbd-mysql-perl \
                python3-mysqldb
            systemctl enable --now mariadb
            mysql --user=root <<'SQL'
DELETE FROM mysql.user WHERE User='';
DELETE FROM mysql.user WHERE User='root' AND Host NOT IN ('localhost','127.0.0.1','::1');
DROP DATABASE IF EXISTS test;
DELETE FROM mysql.db WHERE Db='test' OR Db='test\\_%';
FLUSH PRIVILEGES;
SQL
            ;;
        tumbleweed)
            zypper --non-interactive install -y \
                mariadb mariadb-client mariadb-tools \
                libmariadb-devel \
                mariadb-connector-odbc \
                unixODBC unixODBC-devel \
                python3-mysqlclient
            systemctl enable --now mariadb
            mysql --user=root <<'SQL'
DELETE FROM mysql.user WHERE User='';
DELETE FROM mysql.user WHERE User='root' AND Host NOT IN ('localhost','127.0.0.1','::1');
DROP DATABASE IF EXISTS test;
DELETE FROM mysql.db WHERE Db='test' OR Db='test\\_%';
FLUSH PRIVILEGES;
SQL
            ;;
    esac
    log "MariaDB installed and hardened."
    warn "Run  sudo mysql_secure_installation  to set a root password."
}

# =============================================================================
#  STEP 8 -- GTK 2, 3, 4 + C++ WRAPPERS
# =============================================================================
step8_gtk() {
    section "STEP 8 -- GTK2 / GTK3 / GTK4 + gtkmm C++ Wrappers"
    case "${DISTRO}" in
        debian)
            deb_install \
                libgtk2.0-dev libglib2.0-dev libcairo2-dev \
                libpango1.0-dev libgdk-pixbuf2.0-dev libatk1.0-dev \
                libgtk-3-dev libgtk-3-0 \
                libgtk-4-dev libgtk-4-1 libgraphene-1.0-dev \
                libgtkmm-2.4-dev libgtkmm-3.0-dev libgtkmm-4.0-dev \
                libglibmm-2.4-dev libglibmm-2.68-dev \
                libsigc++-2.0-dev libsigc++-3.0-dev \
                libcairomm-1.0-dev libcairomm-1.16-dev \
                libpangomm-1.4-dev libpangomm-2.48-dev \
                libgirepository1.0-dev gobject-introspection \
                gir1.2-gtk-3.0 gir1.2-gtk-4.0 \
                gtk-update-icon-cache libglade2-dev \
                libdbus-1-dev libdbus-glib-1-dev
            ;;
        tumbleweed)
            zypper --non-interactive install -y \
                gtk2-devel gtk3-devel gtk4-devel \
                glib2-devel cairo-devel pango-devel gdk-pixbuf-devel \
                gtkmm2-devel gtkmm3-devel gtkmm4-devel \
                glibmm2-devel sigc++2-devel sigc++3-devel \
                cairomm-devel gobject-introspection-devel \
                typelib-1_0-Gtk-3_0 typelib-1_0-Gtk-4_0 \
                dbus-1-devel
            ;;
    esac
    log "GTK2/3/4 and C++ wrappers installed."
}

# =============================================================================
#  STEP 9 -- PYTHON 2 & 3
# =============================================================================
step9_python() {
    section "STEP 9 -- Python 2 & 3 Setup + Packages"
    case "${DISTRO}" in
        debian)
            deb_install \
                python3 python3-dev python3-pip python3-venv \
                python3-setuptools python3-wheel python3-tk \
                python3-numpy python3-scipy python3-matplotlib python3-pandas \
                python3-requests python3-yaml python3-toml python3-jinja2 \
                python3-paramiko python3-serial python3-smbus \
                python3-gi python3-gi-cairo \
                python3-mysqldb python3-sqlalchemy \
                python3-pexpect python3-pytest python3-coverage \
                python3-mypy pylint \
                black python3-flake8 \
                python3-sphinx python3-cffi cython3 \
                pipx

            # ── Packages not available in Debian 12 apt repos ────────────────
            log "Installing Python tools unavailable in apt via pip..."
            pip3 install --break-system-packages \
                autopep8 \
                isort \
                jsonpath-ng \
                || warn "pip install of autopep8/isort/jsonpath-ng failed -- install manually."

            # Python 2 (not in Debian 12 official repos -- best-effort)
            apt-cache show python2 &>/dev/null \
                && deb_install python2 python2-dev \
                || warn "Python 2 not available in Debian 12 repos. Use pyenv if required."

            # PEP 668 system-wide pip wrapper
            cat > /usr/local/bin/pip3-system <<'EOF'
#!/usr/bin/env bash
# Wrapper: installs pip packages system-wide on Debian 12 (PEP 668 override)
pip3 install --break-system-packages "$@"
EOF
            chmod +x /usr/local/bin/pip3-system
            ;;
        tumbleweed)
            zypper --non-interactive install -y \
                python3 python3-devel python3-pip python3-venv \
                python3-setuptools python3-wheel python3-tk \
                python3-numpy python3-scipy python3-matplotlib python3-pandas \
                python3-requests python3-PyYAML python3-Jinja2 \
                python3-paramiko python3-pyserial \
                python3-gobject python3-mysqlclient python3-SQLAlchemy \
                python3-pytest pylint black \
                python3-flake8 python3-Sphinx python3-Cython \
                python2 python2-devel || warn "Some packages unavailable."
            ;;
    esac
    log "Python setup complete. $(python3 --version)"
}

# =============================================================================
#  STEP 10 -- DOCKER, PODMAN & CONTAINER TOOLS
# =============================================================================
step10_containers() {
    section "STEP 10 -- Docker CE + Podman + Container Tools"
    case "${DISTRO}" in
        debian)
            deb_install ca-certificates gnupg lsb-release
            install -m 0755 -d /etc/apt/keyrings
            curl -fsSL https://download.docker.com/linux/debian/gpg \
                | gpg --yes --dearmor -o /etc/apt/keyrings/docker.gpg
            chmod a+r /etc/apt/keyrings/docker.gpg
            if [[ ! -f /etc/apt/sources.list.d/docker.list ]]; then
                echo "deb [arch=$(dpkg --print-architecture) signed-by=/etc/apt/keyrings/docker.gpg] \
    https://download.docker.com/linux/debian $(lsb_release -cs) stable" \
                    > /etc/apt/sources.list.d/docker.list
                apt-get update -y
            else
                log "Docker repo already configured -- skipping."
            fi
            deb_install \
                docker-ce docker-ce-cli containerd.io \
                docker-buildx-plugin docker-compose-plugin \
                podman buildah skopeo
            systemctl enable --now docker
            log "Add your user to docker group:  sudo usermod -aG docker \$USER"
            ;;
        tumbleweed)
            zypper --non-interactive install -y \
                docker docker-compose \
                podman buildah skopeo
            systemctl enable --now docker
            ;;
    esac
    log "Container tools installed."
}

# =============================================================================
#  STEP 11 -- CROSS-COMPILATION & QEMU
# =============================================================================
step11_cross_compile() {
    section "STEP 11 -- Cross-Compilation (Raspberry Pi + AVR)"
    case "${DISTRO}" in
        debian)
            # ── Raspberry Pi -- ARM 32-bit (Pi 1/2/3/Zero) ───────────────────
            # Install versioned gcc-12 packages directly -- the meta-packages
            # (gcc-arm-linux-gnueabihf etc.) have broken deps due to third-party
            # repo version conflicts, so we bypass them entirely.
            log "Installing RPi ARM 32-bit toolchain (armhf)..."
            apt-get install -y -t bookworm                 gcc-12-arm-linux-gnueabihf                 g++-12-arm-linux-gnueabihf                 binutils-arm-linux-gnueabihf                 libstdc++-12-dev-armhf-cross                 libc6-dev-armhf-cross                 || warn "armhf toolchain install had errors -- check output."

            # ── Raspberry Pi -- ARM 64-bit (Pi 4/5) ──────────────────────────
            log "Installing RPi ARM 64-bit toolchain (aarch64)..."
            apt-get install -y -t bookworm                 gcc-12-aarch64-linux-gnu                 g++-12-aarch64-linux-gnu                 binutils-aarch64-linux-gnu                 libstdc++-12-dev-arm64-cross                 libc6-dev-arm64-cross                 || warn "aarch64 toolchain install had errors -- check output."

            # ── AVR (Arduino / ATmega) ────────────────────────────────────────
            # Note: g++-avr does not exist separately -- C++ is bundled in gcc-avr
            # Note: simulavr was dropped from Debian 12 repos
            log "Installing AVR toolchain..."
            apt-get install -y \
                gcc-avr \
                avr-libc \
                avrdude \
                binutils-avr \
                gdb-avr

            # ── SDCC (Small Device C Compiler -- PIC, STM8, MCS51, Z80) ─────
            # Covers PIC16/PIC18, STM8, Intel 8051/MCS51, Zilog Z80 and more.
            # Complements AVR toolchain for wider embedded target coverage.
            log "Installing SDCC..."
            apt-get install -y                 sdcc                 sdcc-libraries                 sdcc-doc                 || warn "sdcc install failed -- check apt output."

            # ── QEMU for RPi binary testing on x86 ───────────────────────────
            log "Installing QEMU ARM emulation..."
            apt-get install -y \
                qemu-user-static \
                binfmt-support

            # ── Symlinks so toolchain names resolve without -12 suffix ────────
            log "Creating cross-compiler symlinks..."
            for arch in arm-linux-gnueabihf aarch64-linux-gnu; do
                for tool in gcc g++ cpp; do
                    src="/usr/bin/${arch}-${tool}-12"
                    dst="/usr/bin/${arch}-${tool}"
                    if [[ -f "${src}" ]] && [[ ! -e "${dst}" ]]; then
                        ln -sf "${src}" "${dst}"
                        log "  Linked: ${dst}"
                    fi
                done
            done

            log ""
            log "RPi cross-compile usage:"
            log "  32-bit:  arm-linux-gnueabihf-gcc-12 -o hello hello.c"
            log "  64-bit:  aarch64-linux-gnu-gcc-12   -o hello hello.c"
            log ""
            log "AVR usage:"
            log "  avr-gcc -mmcu=atmega328p -o hello.elf hello.c"
            log "  avrdude -c arduino -p m328p -P /dev/ttyUSB0 -U flash:w:hello.hex"
            ;;

        tumbleweed)
            # ── Raspberry Pi ──────────────────────────────────────────────────
            zypper --non-interactive install -y \
                cross-arm-linux-gnueabihf-gcc \
                cross-arm-linux-gnueabihf-gcc-c++ \
                cross-aarch64-linux-gnu-gcc \
                cross-aarch64-linux-gnu-gcc-c++ \
                qemu-linux-user binfmt-misc

            # ── AVR + SDCC ────────────────────────────────────────────────────
            zypper --non-interactive install -y \
                cross-avr-gcc \
                avr-libc \
                avrdude \
                sdcc
            ;;
    esac
    log "Cross-compilation toolchains installed."
}

# =============================================================================
#  STEP 12 -- NETWORK, IPC & MESSAGING LIBRARIES
# =============================================================================
step12_network_ipc() {
    section "STEP 12 -- Network, IPC & Messaging Libraries"
    case "${DISTRO}" in
        debian)
            deb_install \
                libzmq3-dev libzmq5 \
                libboost-all-dev \
                libprotobuf-dev protobuf-compiler \
                libwebsockets-dev \
                libmicrohttpd-dev \
                libcjson-dev \
                nlohmann-json3-dev \
                rapidjson-dev
            ;;
        tumbleweed)
            zypper --non-interactive install -y \
                zeromq-devel \
                boost-devel \
                protobuf-devel \
                libwebsockets-devel \
                libmicrohttpd-devel \
                cJSON-devel \
                nlohmann_json-devel
            ;;
    esac
    log "Network, IPC and messaging libraries installed."
}

# =============================================================================
#  STEP 13 -- DATABASE EXTRAS (SQLite, PostgreSQL, Redis)
# =============================================================================
step13_database_extras() {
    section "STEP 13 -- Database Extras (SQLite, PostgreSQL client, Redis)"
    case "${DISTRO}" in
        debian)
            deb_install \
                libsqlite3-dev sqlite3 \
                libpq-dev postgresql-client \
                redis-server libhiredis-dev
            systemctl enable --now redis-server
            ;;
        tumbleweed)
            zypper --non-interactive install -y \
                sqlite3 sqlite3-devel \
                postgresql-devel \
                redis hiredis-devel
            systemctl enable --now redis
            ;;
    esac
    log "Database extras installed."
}

# =============================================================================
#  STEP 14 -- TESTING & QUALITY TOOLS
# =============================================================================
step14_testing() {
    section "STEP 14 -- Testing & Code Quality (GTest, lcov, scan-build)"
    case "${DISTRO}" in
        debian)
            deb_install libgtest-dev libgmock-dev lcov gcovr clang-tools
            # Build Google Test as a shared library
            log "Building Google Test library from source..."
            cmake -S /usr/src/googletest \
                  -B /tmp/gtest-build \
                  -DCMAKE_INSTALL_PREFIX=/usr/local \
                  -DBUILD_SHARED_LIBS=ON
            cmake --build /tmp/gtest-build --parallel "$(nproc)"
            cmake --install /tmp/gtest-build
            rm -rf /tmp/gtest-build
            ;;
        tumbleweed)
            zypper --non-interactive install -y \
                gtest lcov python3-gcovr clang-tools
            ;;
    esac
    log "Testing and quality tools installed."
}

# =============================================================================
#  STEP 15 -- NODE.JS (NodeSource -- latest LTS)
# =============================================================================
step15_nodejs() {
    section "STEP 15 -- Node.js ${NODE_MAJOR}.x LTS (via NodeSource)"

    # ── NOTE ON VERSION SAFETY ────────────────────────────────────────────────
    # Debian 12 ships Node.js 18.x in its main repo -- already behind.
    # NodeSource provides the official current LTS (currently 22.x).
    # NODE_MAJOR is set at the top of this script -- change it there if needed.
    # ─────────────────────────────────────────────────────────────────────────

    case "${DISTRO}" in
        debian)
            deb_install ca-certificates gnupg curl
            install -m 0755 -d /etc/apt/keyrings
            curl -fsSL https://deb.nodesource.com/gpgkey/nodesource-repo.gpg.key \
                | gpg --yes --dearmor -o /etc/apt/keyrings/nodesource.gpg
            if [[ ! -f /etc/apt/sources.list.d/nodesource.list ]]; then
                echo "deb [signed-by=/etc/apt/keyrings/nodesource.gpg] \
    https://deb.nodesource.com/node_${NODE_MAJOR}.x nodistro main" \
                    > /etc/apt/sources.list.d/nodesource.list
                apt-get update -y
            else
                log "NodeSource repo already configured -- skipping."
            fi
            deb_install nodejs
            ;;
        tumbleweed)
            # Tumbleweed ships a current Node.js; use it directly
            zypper --non-interactive install -y nodejs npm
            ;;
    esac

    # ── Global npm packages ───────────────────────────────────────────────────
    log "Installing global npm packages..."
    npm install -g \
        npm@latest \
        yarn \
        pnpm \
        typescript \
        ts-node \
        tsx \
        nodemon \
        pm2 \
        eslint \
        prettier \
        @biomejs/biome \
        jest \
        dotenv-cli \
        http-server \
        wscat \
        node-gyp \
        npm-check-updates

    log "Node.js $(node --version) + npm $(npm --version) installed."
}

# =============================================================================
#  STEP 16 -- PHP (Ondrej Sury repo on Debian -- 8.3/8.4 current)
# =============================================================================
step16_php() {
    section "STEP 16 -- PHP ${PHP_VERSION} + Extensions"

    # ── NOTE ON VERSION SAFETY ────────────────────────────────────────────────
    # Debian 12 ships PHP 8.2 in main repos.
    # packages.sury.org (Ondrej Sury) provides PHP 8.3 and 8.4 for Debian.
    # This is the canonical, widely-trusted third-party PHP source for Debian.
    # PHP_VERSION is set at the top of this script.
    # ─────────────────────────────────────────────────────────────────────────

    case "${DISTRO}" in
        debian)
            deb_install apt-transport-https lsb-release ca-certificates curl
            curl -sSLo /tmp/php-sury.gpg https://packages.sury.org/php/apt.gpg
            install -o root -g root -m 644 /tmp/php-sury.gpg \
                /etc/apt/trusted.gpg.d/php-sury.gpg
            if [[ ! -f /etc/apt/sources.list.d/php-sury.list ]]; then
                rm /tmp/php-sury.gpg
                echo "deb https://packages.sury.org/php/ $(lsb_release -sc) main" \
                    > /etc/apt/sources.list.d/php-sury.list
                apt-get update -y
            else
                log "PHP Sury repo already configured -- skipping."
            fi

            P="php${PHP_VERSION}"
            deb_install \
                "${P}" \
                "${P}-cli" \
                "${P}-fpm" \
                "${P}-common" \
                "${P}-mysql" \
                "${P}-pgsql" \
                "${P}-sqlite3" \
                "${P}-mbstring" \
                "${P}-xml" \
                "${P}-xmlrpc" \
                "${P}-soap" \
                "${P}-curl" \
                "${P}-zip" \
                "${P}-gd" \
                "${P}-intl" \
                "${P}-bcmath" \
                "${P}-opcache" \
                "${P}-redis" \
                "${P}-memcached" \
                "${P}-xdebug" \
                "${P}-dev" \
                "${P}-odbc" \
                "${P}-ldap" \
                php-pear

            update-alternatives --set php "/usr/bin/php${PHP_VERSION}" 2>/dev/null || true

            # ── Disable PEAR auto-update -- it hangs waiting for network ──────
            # pear auto_discover and channel updates stall indefinitely.
            # Disable them; user can run  pear update-channels  manually later.
            log "Configuring PEAR to prevent network hang..."
            pear config-set auto_discover 0 2>/dev/null || true
            pear config-set preferred_state stable 2>/dev/null || true

            # ── Enable php-fpm without blocking on service start ──────────────
            log "Enabling php${PHP_VERSION}-fpm service..."
            systemctl enable "php${PHP_VERSION}-fpm" || true
            # Use start with timeout rather than enable --now which can hang
            timeout 30 systemctl start "php${PHP_VERSION}-fpm"                 && log "php-fpm started."                 || warn "php-fpm start timed out -- start manually: systemctl start php${PHP_VERSION}-fpm"
            ;;
        tumbleweed)
            zypper --non-interactive install -y \
                php8 php8-cli php8-fpm \
                php8-mysql php8-pgsql php8-sqlite \
                php8-mbstring php8-xml php8-xmlrpc \
                php8-soap php8-curl php8-zip \
                php8-gd php8-intl php8-bcmath \
                php8-opcache php8-redis php8-xdebug \
                php8-devel php8-pear
            ;;
    esac

    # ── Composer -- install manually after script completes ──────────────────
    log "Skipping Composer auto-install (see COMPOSER_INSTALL.md for instructions)."
    cat > /root/COMPOSER_INSTALL.md <<'README'
# Installing Composer (PHP Dependency Manager)

Composer was not installed automatically to avoid network timeout issues.
Run the following commands manually when ready:

## Step 1 -- Download the installer
    curl -fsSL https://getcomposer.org/installer -o /tmp/composer-setup.php

## Step 2 -- Verify the checksum (recommended)
    EXPECTED=$(curl -fsSL https://composer.github.io/installer.sig)
    ACTUAL=$(php -r "echo hash_file('sha384', '/tmp/composer-setup.php');")
    echo "Expected : $EXPECTED"
    echo "Actual   : $ACTUAL"
    # The two values above must match before proceeding

## Step 3 -- Install Composer globally
    sudo php /tmp/composer-setup.php         --install-dir=/usr/local/bin         --filename=composer         --2
    rm /tmp/composer-setup.php

## Step 4 -- Verify installation
    composer --version

## Step 5 -- Keep Composer updated
    sudo composer self-update

## Daily usage
    composer require vendor/package        # add a dependency
    composer install                       # install from composer.json
    composer update                        # update all dependencies
    composer dump-autoload                 # rebuild autoloader

## Official documentation
    https://getcomposer.org/doc/
README

    log "Composer install instructions written to: /root/COMPOSER_INSTALL.md"
    log "PHP ${PHP_VERSION} setup complete."
}

# =============================================================================
#  STEP 17 -- PERL + CORE MODULES + cpanm
# =============================================================================
step17_perl() {
    section "STEP 17 -- Perl + DBI/DBD Modules + cpanm"

    # ── NOTE ON VERSION SAFETY ────────────────────────────────────────────────
    # Debian 12 ships Perl 5.36. This is current stable as of Bookworm.
    # All modules are installed via apt (python3-style python3-<pkg> equivalent
    # is libXXX-perl in Perl's case). cpanm covers anything not in apt.
    # ─────────────────────────────────────────────────────────────────────────

    case "${DISTRO}" in
        debian)
            deb_install \
                perl perl-doc \
                cpanminus \
                libdbi-perl \
                libdbd-mysql-perl \
                libdbd-sqlite3-perl \
                libdbd-pg-perl \
                libjson-perl \
                libjson-xs-perl \
                libxml-libxml-perl \
                libxml-simple-perl \
                libwww-perl \
                liburi-perl \
                libyaml-perl \
                libmoose-perl \
                libpath-tiny-perl \
                liblog-log4perl-perl \
                libcgi-pm-perl \
                libtemplate-perl \
                libnet-ssleay-perl \
                libio-socket-ssl-perl \
                libdigest-sha-perl

            log "Updating cpanm itself..."
            cpanm --notest App::cpanminus
            ;;
        tumbleweed)
            zypper --non-interactive install -y \
                perl perl-CPAN \
                perl-DBI perl-DBD-mysql \
                perl-DBD-SQLite perl-DBD-Pg \
                perl-JSON perl-JSON-XS \
                perl-XML-LibXML perl-libwww-perl \
                perl-YAML perl-Moose \
                perl-CGI perl-Template-Toolkit \
                perl-Net-SSLeay perl-IO-Socket-SSL
            ;;
    esac

    log "Perl installed. Install further modules:  cpanm <Module::Name>"
}

# =============================================================================
#  STEP 18 -- JSON TOOLS (CLI + C/C++ libraries)
# =============================================================================
step18_json_tools() {
    section "STEP 18 -- JSON Libraries & CLI Tools"
    case "${DISTRO}" in
        debian)
            deb_install \
                jq \
                nlohmann-json3-dev \
                rapidjson-dev \
                libjansson-dev \
                libcjson-dev \
                libjson-c-dev \
                python3-jsonschema \
            ;;
        tumbleweed)
            zypper --non-interactive install -y \
                jq \
                nlohmann_json-devel \
                rapidjson-devel \
                libjansson-devel \
                cJSON-devel \
                libjson-c-devel \
                python3-jsonschema
            ;;
    esac

    # Node.js JSON CLI extras (if node is available)
    if command -v npm &>/dev/null; then
        log "Installing Node.js JSON utilities (fx, json5, ajv-cli)..."
        npm install -g fx json5 ajv-cli
    fi

    log "JSON tools installed."
    log "Usage:  jq '.' file.json  |  fx file.json  |  python3 -m json.tool file.json"
}

# =============================================================================
#  STEP 19 -- NETWORKING TOOLS
# =============================================================================
step19_network_tools() {
    section "STEP 19 -- Networking Tools (Diagnostic, Scan, Transfer & Classic)"
    case "${DISTRO}" in
        debian)
            # ── Pre-answer debconf to suppress interactive prompts ────────────
            # Prevents iperf3 daemon dialog hanging the script
            echo "iperf3 iperf3/start_daemon boolean false" | debconf-set-selections 2>/dev/null || true
            DEBIAN_FRONTEND=noninteractive apt-get install -y debconf-utils 2>/dev/null || true

            deb_install \
                `# ── Discovery & Scanning ──────────────────────────────────` \
                nmap \
                ncat \
                masscan \
                arp-scan \
                nbtscan \
                `# ── Diagnostics & Routing ─────────────────────────────────` \
                iputils-ping \
                iputils-tracepath \
                traceroute \
                mtr \
                iproute2 \
                net-tools \
                whois \
                dnsutils \
                bind9-dnsutils \
                `# ── Classic / Legacy Tools ────────────────────────────────` \
                telnet \
                ftp \
                tftp \
                rsh-client \
                lftp \
                ncftp \
                `# ── File Transfer & Download ──────────────────────────────` \
                wget \
                curl \
                aria2 \
                axel \
                `# ── Packet Analysis & Capture ─────────────────────────────` \
                tcpdump \
                wireshark-common \
                tshark \
                termshark \
                ettercap-text-only \
                `# ── Bandwidth & Performance ───────────────────────────────` \
                iperf3 \
                iperf \
                speedtest-cli \
                `# ── Port & Socket Tools ───────────────────────────────────` \
                netcat-openbsd \
                socat \
                nmap \
                lsof \
                `# ── SSH / Tunnelling ──────────────────────────────────────` \
                sshpass \
                autossh \
                proxychains4 \
                `# ── SNMP & Network Management ─────────────────────────────` \
                snmp \
                snmpd \
                `# ── HTTP / REST Testing ───────────────────────────────────` \
                httpie \
                `# ── Wireless (useful even on dev boxes) ───────────────────` \
                wireless-tools \
                iw \
                wavemon

            # ── SNMP MIBs -- requires non-free repo ──────────────────────────
            # snmp-mibs-downloader lives in non-free component only.
            # Debian 12 uses /etc/apt/sources.list.d/ style -- we write a
            # ── Enable non-free in sources.list in-place ─────────────────────
            # Modifies existing deb lines in /etc/apt/sources.list directly
            # rather than writing a new .list file -- the only safe way to
            # avoid "configured multiple times" duplicate warnings.
            # Also removes any legacy non-free.list from previous script runs.
            log "Enabling non-free components in /etc/apt/sources.list..."

            # Remove legacy non-free.list from earlier script versions
            if [[ -f /etc/apt/sources.list.d/non-free.list ]]; then
                log "Removing legacy non-free.list to prevent duplicates..."
                rm -f /etc/apt/sources.list.d/non-free.list
            fi

            # Rewrite sources.list -- append non-free and non-free-firmware
            # to any deb line that doesn't already have them.
            TMP_SRC=$(mktemp)
            while IFS= read -r line; do
                if [[ "${line}" =~ ^deb[[:space:]] ]]; then
                    # Add non-free-firmware if absent
                    [[ "${line}" == *"non-free-firmware"* ]] \
                        || line="${line} non-free-firmware"
                    # Add non-free if absent (word-boundary safe)
                    if ! echo "${line}" | grep -qw "non-free$\|non-free "; then
                        line=$(echo "${line}" | \
                            sed "s/non-free-firmware/non-free non-free-firmware/")
                    fi
                fi
                echo "${line}"
            done < /etc/apt/sources.list > "${TMP_SRC}"
            mv "${TMP_SRC}" /etc/apt/sources.list
            log "sources.list updated with non-free components."

            apt-get update -y
            apt-get install -y snmp-mibs-downloader \
                && log "snmp-mibs-downloader installed -- test: snmptranslate -m all -IR sysDescr.0" \
                || warn "snmp-mibs-downloader unavailable -- ensure non-free is in sources.list"
            ;;
        tumbleweed)
            zypper --non-interactive install -y \
                nmap ncat masscan arp-scan nbtscan \
                iputils traceroute mtr iproute2 net-tools \
                whois bind-utils \
                telnet ftp tftp lftp ncftp \
                wget curl aria2 axel \
                tcpdump wireshark tshark \
                netcat-openbsd socat lsof \
                sshpass autossh proxychains-ng \
                net-snmp net-snmp-utils \
                httpie \
                wireless-tools iw wavemon
            ;;
    esac

    # ── Allow non-root users to capture packets (Wireshark/tshark) ───────────
    if getent group wireshark &>/dev/null; then
        log "Wireshark group exists -- add your user with:"
        log "  sudo usermod -aG wireshark \$USER"
    fi

    # ── Install hping3 from source if not in repo ─────────────────────────────
    if ! command -v hping3 &>/dev/null; then
        if [[ "${DISTRO}" == "debian" ]]; then
            deb_install hping3 2>/dev/null \
                || warn "hping3 not in repo -- install manually if needed."
        fi
    fi

    log "Networking tools installed."
    log ""
    log "Quick reference:"
    log "  nmap -sV -p- <host>          -- full port + version scan"
    log "  mtr <host>                   -- real-time traceroute + ping"
    log "  tcpdump -i eth0 port 80      -- live packet capture"
    log "  tshark -i eth0 -w out.pcap   -- Wireshark CLI capture"
    log "  iperf3 -s / iperf3 -c <host> -- bandwidth test server/client"
    log "  socat TCP-LISTEN:9999,fork - -- netcat-style listener"
    log "  httpie http GET example.com  -- human-friendly HTTP client"
    log "  aria2c -x16 <url>            -- multi-threaded download"
}

# =============================================================================
#  STEP 20 -- SSH SERVER + RSYNC + REMOTE TOOLS
# =============================================================================
step20_remote_tools() {
    section "STEP 20 -- OpenSSH Server + Remote Tools"
    case "${DISTRO}" in
        debian)
            deb_install openssh-server rsync
            systemctl enable --now ssh
            ;;
        tumbleweed)
            zypper --non-interactive install -y openssh rsync
            systemctl enable --now sshd
            ;;
    esac
    log "SSH server enabled."
    log "Harden SSH:  sudo nano /etc/ssh/sshd_config"
    log "  Recommended: PasswordAuthentication no, PermitRootLogin no"
}

# =============================================================================
#  SUMMARY REPORT
# =============================================================================
print_summary() {
    section "Installation Complete -- Summary"

    echo -e "${BOLD}Distribution :${RESET}  ${DISTRO_NAME} ${DISTRO_VERSION}"
    echo -e "${BOLD}Node.js      :${RESET}  $(node --version 2>/dev/null || echo 'verify manually')"
    echo -e "${BOLD}npm          :${RESET}  $(npm --version 2>/dev/null || echo 'verify manually')"
    echo -e "${BOLD}PHP          :${RESET}  $(php --version 2>/dev/null | head -1 || echo 'verify manually')"
    echo -e "${BOLD}Composer     :${RESET}  See /root/COMPOSER_INSTALL.md"
    echo -e "${BOLD}Python3      :${RESET}  $(python3 --version 2>/dev/null || echo 'verify manually')"
    echo -e "${BOLD}Perl         :${RESET}  $(perl --version 2>/dev/null | head -2 | tail -1 || echo 'verify manually')"
    echo -e "${BOLD}MariaDB      :${RESET}  $(mysql --version 2>/dev/null || echo 'verify manually')"
    echo -e "${BOLD}Docker       :${RESET}  $(docker --version 2>/dev/null || echo 'verify manually')"
    echo ""
    for i in \
        " 0  Broken dependencies fixed, held packages resolved, libcurl pinned" \
        " 1  System updated & upgraded" \
        " 2  i386 / 32-bit architecture enabled" \
        " 3  Build-essential toolchain" \
        " 4  Core dev tools (cmake, ninja, clang, lld, gdb, lldb, strace, ccache...)" \
        " 5  Docs & analysis (doxygen, plantuml, cppcheck, bear, iwyu, shellcheck, pandoc)" \
        " 6  Hardware libs (gpiod, i2c, modbus, CAN bus, USB, MQTT, openssl, curl)" \
        " 7  MariaDB (server + client + backup + ODBC + connectors)" \
        " 8  GTK 2/3/4 + gtkmm C++ wrappers + sigc++ + cairomm + D-Bus" \
        " 9  Python 2 & 3 + scientific, DB, test, lint, doc packages" \
        "10  Docker CE + Podman + buildah + skopeo + docker-compose" \
        "11  Cross-compilation (RPi armhf + aarch64, AVR + QEMU)" \
        "12  ZeroMQ, Boost, Protobuf, WebSockets, microhttpd, JSON libs" \
        "13  SQLite, PostgreSQL client, Redis + hiredis" \
        "14  Google Test + gmock (built), lcov, gcovr, clang-analyzer" \
        "15  Node.js ${NODE_MAJOR}.x LTS (NodeSource) + yarn/pnpm/ts/eslint/jest/pm2" \
        "16  PHP ${PHP_VERSION} (Sury repo) + full extension set (Composer: see /root/COMPOSER_INSTALL.md)" \
        "17  Perl 5 + DBI/DBD (MySQL, SQLite, PG) + JSON/XML/YAML + cpanm" \
        "18  JSON tools: jq, nlohmann, rapidjson, jansson, fx, ajv-cli" \
        "19  Networking tools (nmap, masscan, mtr, tcpdump, tshark, telnet, ftp, iperf3, socat, httpie...)" \
        "20  OpenSSH server + rsync"; do
        echo -e "${GREEN}[OK]${RESET} Step ${i}"
    done

    echo ""
    echo -e "${BOLD}${YELLOW}Post-install checklist:${RESET}"
    echo "  sudo mysql_secure_installation          -- set MariaDB root password"
    echo "  sudo usermod -aG docker \$USER && newgrp docker  -- docker without sudo"
    echo "  python3 -m venv ~/.venvs/project        -- isolated Python project"
    echo "  pip3-system <pkg>                       -- system-wide pip (Debian 12)"
    echo "  cat /root/COMPOSER_INSTALL.md           -- install Composer when ready"
    echo "  cpanm Module::Name                      -- Perl module via CPAN"
    echo "  ncu -g                                  -- check outdated global npm packages"
    echo "  sudo nano /etc/ssh/sshd_config          -- harden SSH"
    echo ""
    echo -e "${CYAN}Script complete. A reboot is recommended.${RESET}"
    echo ""
}

# =============================================================================
#  MAIN
# =============================================================================
main() {
    clear
    echo -e "\n${BOLD}${CYAN}"
    cat <<'BANNER'
  +============================================================+
  |    Professional Development Environment Installer v2.0     |
  |    Debian 12 Bookworm  |  OpenSUSE Tumbleweed              |
  +============================================================+
BANNER
    echo -e "${RESET}"

    detect_distro

    echo -e "\n${BOLD}Steps to be executed:${RESET}"
    echo "   0.  Fix broken dependencies & conflicts (runs first)"
    echo "   1.  System update & upgrade"
    echo "   2.  i386 / 32-bit architecture"
    echo "   3.  Build-essential toolchain"
    echo "   4.  Core dev tools (cmake, clang, gdb, lldb, lld, strace...)"
    echo "   5.  Docs & static analysis (doxygen, cppcheck, iwyu, shellcheck...)"
    echo "   6.  Hardware/embedded libs (gpiod, i2c, modbus, CAN, MQTT, USB)"
    echo "   7.  MariaDB (full professional stack + ODBC)"
    echo "   8.  GTK 2/3/4 + gtkmm C++ wrappers + D-Bus"
    echo "   9.  Python 2 & 3 + packages"
    echo "  10.  Docker CE + Podman + container tools"
    echo "  11.  Cross-compilation (ARM / AArch64 / RISC-V + QEMU)"
    echo "  12.  Network & IPC (ZeroMQ, Boost, Protobuf, WebSockets)"
    echo "  13.  Database extras (SQLite, PostgreSQL client, Redis)"
    echo "  14.  Testing & quality (GTest, lcov, gcovr, scan-build)"
    echo "  15.  Node.js ${NODE_MAJOR}.x LTS via NodeSource + global tools"
    echo "  16.  PHP ${PHP_VERSION} via Sury repo + full extensions (Composer via readme)"
    echo "  17.  Perl + DBI/DBD modules + cpanm"
    echo "  18.  JSON libs & CLI tools (jq, nlohmann, rapidjson, fx)"
    echo "  19.  Networking tools (nmap, mtr, tcpdump, telnet, ftp, iperf3...)"
    echo "  20.  OpenSSH server + rsync"
    echo ""
    read -rp "Proceed with full installation? [Y/n] " confirm
    [[ "${confirm,,}" == "n" ]] && { log "Aborted by user."; exit 0; }

    step0_fix_dependencies
    step1_system_update
    step2_enable_i386
    step3_build_essential
    step4_developer_tools
    step5_doc_and_analysis
    step6_hardware_libs
    step7_mariadb
    step8_gtk
    step9_python
    step10_containers
    step11_cross_compile
    step12_network_ipc
    step13_database_extras
    step14_testing
    step15_nodejs
    step16_php
    step17_perl
    step18_json_tools
    step19_network_tools
    step20_remote_tools

    print_summary
}

main "$@"
