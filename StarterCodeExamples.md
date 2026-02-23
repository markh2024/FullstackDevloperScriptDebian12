# Starter Code Examples
### Quick-start guides for the installed development stack

---

## Table of Contents

1. [Boost C++ — Compile & Run](#1-boost-c--compile--run)
2. [PHP — Command Line Usage](#2-php--command-line-usage)
3. [Cross-Compilation for Raspberry Pi](#3-cross-compilation-for-raspberry-pi)
4. [Perl — Getting Started](#4-perl--getting-started)
5. [Docker — Getting Started](#5-docker--getting-started)

---

## 1. Boost C++ — Compile & Run

Boost is installed system-wide via `libboost-all-dev`. No special setup is needed —
just include the headers and link the libraries you use.

### 1.1 — Header-Only (No Linking Required)

Many Boost libraries are header-only, meaning no `-l` flag is needed at all.

**Example: Boost.Lexical_Cast**

```cpp
// boost_lexical.cpp
#include <iostream>
#include <boost/lexical_cast.hpp>

int main() {
    std::string s = "42";
    int n = boost::lexical_cast<int>(s);
    std::cout << "String '" << s << "' cast to int: " << n << std::endl;

    double d = boost::lexical_cast<double>("3.14159");
    std::cout << "String '3.14159' cast to double: " << d << std::endl;
    return 0;
}
```

```bash
g++ -std=c++17 -o boost_lexical boost_lexical.cpp
./boost_lexical
```

---

**Example: Boost.Filesystem**

```cpp
// boost_fs.cpp
#include <iostream>
#include <boost/filesystem.hpp>

namespace fs = boost::filesystem;

int main() {
    fs::path p = fs::current_path();
    std::cout << "Current directory : " << p << std::endl;
    std::cout << "Exists            : " << fs::exists(p) << std::endl;
    std::cout << "Is directory      : " << fs::is_directory(p) << std::endl;

    std::cout << "\nContents:" << std::endl;
    for (const auto& entry : fs::directory_iterator(p)) {
        std::cout << "  " << entry.path().filename() << std::endl;
    }
    return 0;
}
```

```bash
# Filesystem requires linking
g++ -std=c++17 -o boost_fs boost_fs.cpp -lboost_filesystem -lboost_system
./boost_fs
```

---

### 1.2 — Boost.Asio (Networking / Async I/O)

```cpp
// boost_asio_timer.cpp
// Simple async timer -- foundation of all Boost.Asio programs
#include <iostream>
#include <boost/asio.hpp>

int main() {
    boost::asio::io_context io;

    // Create a timer that fires after 2 seconds
    boost::asio::steady_timer timer(io, boost::asio::chrono::seconds(2));

    timer.async_wait([](const boost::system::error_code& ec) {
        if (!ec) {
            std::cout << "Timer fired after 2 seconds!" << std::endl;
        }
    });

    std::cout << "Waiting for timer..." << std::endl;
    io.run();   // blocks until all async work is done
    return 0;
}
```

```bash
g++ -std=c++17 -o boost_asio boost_asio_timer.cpp -lboost_system -pthread
./boost_asio
```

---

### 1.3 — Boost.Thread

```cpp
// boost_thread.cpp
#include <iostream>
#include <boost/thread.hpp>
#include <boost/thread/mutex.hpp>

boost::mutex io_mutex;

void worker(int id) {
    boost::mutex::scoped_lock lock(io_mutex);
    std::cout << "Thread " << id << " running on thread id: "
              << boost::this_thread::get_id() << std::endl;
}

int main() {
    boost::thread_group threads;

    for (int i = 0; i < 4; ++i) {
        threads.create_thread(boost::bind(worker, i));
    }

    threads.join_all();
    std::cout << "All threads complete." << std::endl;
    return 0;
}
```

```bash
g++ -std=c++17 -o boost_thread boost_thread.cpp -lboost_thread -lboost_system -pthread
./boost_thread
```

---

### 1.4 — Boost.Program_options (CLI Argument Parsing)

```cpp
// boost_opts.cpp
#include <iostream>
#include <boost/program_options.hpp>

namespace po = boost::program_options;

int main(int argc, char* argv[]) {
    po::options_description desc("Allowed options");
    desc.add_options()
        ("help,h",                          "Show this help message")
        ("name,n",  po::value<std::string>(),"Your name")
        ("count,c", po::value<int>()->default_value(1), "Repeat count");

    po::variables_map vm;
    po::store(po::parse_command_line(argc, argv, desc), vm);
    po::notify(vm);

    if (vm.count("help") || !vm.count("name")) {
        std::cout << desc << std::endl;
        return 0;
    }

    std::string name  = vm["name"].as<std::string>();
    int         count = vm["count"].as<int>();

    for (int i = 0; i < count; ++i) {
        std::cout << "Hello, " << name << "!" << std::endl;
    }
    return 0;
}
```

```bash
g++ -std=c++17 -o boost_opts boost_opts.cpp -lboost_program_options
./boost_opts --name Alice --count 3
./boost_opts --help
```

---

### 1.5 — Using CMake with Boost (Recommended for Projects)

```cmake
# CMakeLists.txt
cmake_minimum_required(VERSION 3.16)
project(BoostExample CXX)

set(CMAKE_CXX_STANDARD 17)

find_package(Boost REQUIRED COMPONENTS
    filesystem
    system
    thread
    program_options
)

add_executable(myapp main.cpp)
target_link_libraries(myapp
    Boost::filesystem
    Boost::system
    Boost::thread
    Boost::program_options
    Threads::Threads
)

find_package(Threads REQUIRED)
```

```bash
mkdir build && cd build
cmake ..
make -j$(nproc)
./myapp
```

---

## 2. PHP — Command Line Usage

PHP runs perfectly from the terminal without a web server. The `php` binary was
installed and set as the system default during setup.

### 2.1 — Verify PHP is Working

```bash
php --version
# PHP 8.3.x (cli) ...

php -r "echo 'Hello from PHP ' . PHP_VERSION . PHP_EOL;"
```

---

### 2.2 — Your First PHP Script

```php
<?php
// hello.php

$name    = "Developer";
$version = PHP_VERSION;
$os      = PHP_OS;

echo "Hello, {$name}!" . PHP_EOL;
echo "Running PHP {$version} on {$os}" . PHP_EOL;

// Arrays
$languages = ["C", "C++", "PHP", "Python", "Perl"];
echo "\nLanguages installed on this machine:" . PHP_EOL;
foreach ($languages as $i => $lang) {
    echo "  {$i}: {$lang}" . PHP_EOL;
}

// Date and time
echo "\nCurrent date/time: " . date("Y-m-d H:i:s") . PHP_EOL;
```

```bash
php hello.php
```

---

### 2.3 — PHP with MariaDB (PDO)

```php
<?php
// db_example.php
// Connects to MariaDB, creates a test table, inserts and reads data

$host   = '127.0.0.1';
$db     = 'test_db';
$user   = 'root';
$pass   = '';           // set your root password here
$port   = '3306';

try {
    $dsn = "mysql:host={$host};port={$port};charset=utf8mb4";
    $pdo = new PDO($dsn, $user, $pass, [
        PDO::ATTR_ERRMODE => PDO::ERRMODE_EXCEPTION,
    ]);

    // Create database and table
    $pdo->exec("CREATE DATABASE IF NOT EXISTS {$db}");
    $pdo->exec("USE {$db}");
    $pdo->exec("CREATE TABLE IF NOT EXISTS users (
        id    INT AUTO_INCREMENT PRIMARY KEY,
        name  VARCHAR(100) NOT NULL,
        email VARCHAR(100) NOT NULL,
        created_at TIMESTAMP DEFAULT CURRENT_TIMESTAMP
    )");

    // Insert
    $stmt = $pdo->prepare("INSERT INTO users (name, email) VALUES (?, ?)");
    $stmt->execute(["Alice", "alice@example.com"]);
    $stmt->execute(["Bob",   "bob@example.com"]);
    echo "Inserted 2 users." . PHP_EOL;

    // Read
    $rows = $pdo->query("SELECT * FROM users")->fetchAll(PDO::FETCH_ASSOC);
    echo "\nUsers in database:" . PHP_EOL;
    foreach ($rows as $row) {
        echo "  [{$row['id']}] {$row['name']} — {$row['email']}" . PHP_EOL;
    }

    // Cleanup
    $pdo->exec("DROP DATABASE {$db}");
    echo "\nTest database cleaned up." . PHP_EOL;

} catch (PDOException $e) {
    echo "Error: " . $e->getMessage() . PHP_EOL;
}
```

```bash
php db_example.php
```

---

### 2.4 — PHP JSON Handling

```php
<?php
// json_example.php

// Encode PHP array to JSON
$data = [
    "project" => "MyApp",
    "version" => "1.0.0",
    "features" => ["auth", "api", "database"],
    "config"   => ["debug" => true, "port" => 8080],
];

$json = json_encode($data, JSON_PRETTY_PRINT);
echo "JSON output:" . PHP_EOL . $json . PHP_EOL;

// Decode JSON string back to PHP
$decoded = json_decode($json, true);
echo "\nProject name : " . $decoded['project'] . PHP_EOL;
echo "First feature: " . $decoded['features'][0] . PHP_EOL;
echo "Port         : " . $decoded['config']['port'] . PHP_EOL;
```

```bash
php json_example.php

# Pipe output through jq for pretty printing from shell
php -r "echo json_encode(['key' => 'value', 'num' => 42]);" | jq .
```

---

### 2.5 — Running PHP as an Interactive REPL

```bash
# Interactive shell (like Python's REPL)
php -a

# Then type PHP directly:
php > echo date('Y-m-d');
php > $x = [1, 2, 3]; print_r(array_sum($x));
php > exit
```

---

## 3. Cross-Compilation for Raspberry Pi

All examples assume you are compiling **on your Debian 12 development machine**
and deploying the resulting binary **to a Raspberry Pi**.

### 3.1 — Toolchain Quick Reference

| Target | Pi Models | Compiler |
|--------|-----------|----------|
| `arm-linux-gnueabihf` | Pi 1, 2, 3, Zero, Zero W | `arm-linux-gnueabihf-gcc-12` |
| `aarch64-linux-gnu` | Pi 4, Pi 5 | `aarch64-linux-gnu-gcc-12` |

---

### 3.2 — Hello World — Pi 4 / Pi 5 (64-bit aarch64)

```c
// hello_rpi.c
#include <stdio.h>

int main(void) {
    printf("Hello from the Raspberry Pi!\n");
    printf("Compiled with aarch64 cross-compiler on host machine.\n");
    return 0;
}
```

```bash
# Compile on your Debian 12 host
aarch64-linux-gnu-gcc-12 -o hello_rpi hello_rpi.c

# Check the binary is really ARM64
file hello_rpi
# hello_rpi: ELF 64-bit LSB executable, ARM aarch64...

# Copy to the Pi and run it there
scp hello_rpi pi@<pi-ip-address>:~/
ssh pi@<pi-ip-address> ./hello_rpi

# Or test locally using QEMU (no Pi hardware needed)
qemu-aarch64-static hello_rpi
```

---

### 3.3 — Hello World — Pi 1 / 2 / 3 / Zero (32-bit armhf)

```c
// hello_rpi32.c
#include <stdio.h>

int main(void) {
    printf("Hello from a 32-bit Raspberry Pi!\n");
    return 0;
}
```

```bash
# Compile for 32-bit ARM
arm-linux-gnueabihf-gcc-12 -o hello_rpi32 hello_rpi32.c

# Verify the architecture
file hello_rpi32
# hello_rpi32: ELF 32-bit LSB executable, ARM, EABI5...

# Test with QEMU
qemu-arm-static hello_rpi32

# Deploy to the Pi
scp hello_rpi32 pi@<pi-ip-address>:~/
ssh pi@<pi-ip-address> ./hello_rpi32
```

---

### 3.4 — GPIO Blink Example (aarch64, using libgpiod)

```c
// gpio_blink.c
// Blinks GPIO pin 17 on a Raspberry Pi 4/5
// Requires libgpiod-dev on the Pi as well as the host cross-sysroot
#include <stdio.h>
#include <unistd.h>
#include <gpiod.h>

#define GPIO_CHIP   "/dev/gpiochip0"
#define GPIO_PIN    17
#define BLINK_COUNT 5

int main(void) {
    struct gpiod_chip *chip;
    struct gpiod_line *line;

    chip = gpiod_chip_open(GPIO_CHIP);
    if (!chip) { perror("gpiod_chip_open"); return 1; }

    line = gpiod_chip_get_line(chip, GPIO_PIN);
    if (!line) { perror("gpiod_chip_get_line"); return 1; }

    if (gpiod_line_request_output(line, "blink", 0) < 0) {
        perror("gpiod_line_request_output");
        return 1;
    }

    printf("Blinking GPIO %d, %d times...\n", GPIO_PIN, BLINK_COUNT);
    for (int i = 0; i < BLINK_COUNT; i++) {
        gpiod_line_set_value(line, 1);   // HIGH
        sleep(1);
        gpiod_line_set_value(line, 0);   // LOW
        sleep(1);
    }

    gpiod_line_release(line);
    gpiod_chip_close(chip);
    printf("Done.\n");
    return 0;
}
```

```bash
# NOTE: For GPIO you need the Pi's sysroot or the gpiod headers for ARM.
# Simplest approach -- compile natively on the Pi itself via SSH:
ssh pi@<pi-ip-address>
sudo apt install libgpiod-dev gcc
gcc -o gpio_blink gpio_blink.c -lgpiod
sudo ./gpio_blink
```

---

### 3.5 — CMakeLists.txt for Cross-Compilation

```cmake
# CMakeLists.txt
cmake_minimum_required(VERSION 3.16)
project(RpiApp C CXX)
set(CMAKE_CXX_STANDARD 17)

add_executable(rpi_app main.cpp)
```

```cmake
# toolchain-aarch64.cmake  -- pass this to cmake with -DCMAKE_TOOLCHAIN_FILE=
set(CMAKE_SYSTEM_NAME Linux)
set(CMAKE_SYSTEM_PROCESSOR aarch64)

set(CMAKE_C_COMPILER   aarch64-linux-gnu-gcc-12)
set(CMAKE_CXX_COMPILER aarch64-linux-gnu-g++-12)

set(CMAKE_FIND_ROOT_PATH_MODE_PROGRAM NEVER)
set(CMAKE_FIND_ROOT_PATH_MODE_LIBRARY ONLY)
set(CMAKE_FIND_ROOT_PATH_MODE_INCLUDE ONLY)
```

```bash
mkdir build-rpi && cd build-rpi
cmake .. -DCMAKE_TOOLCHAIN_FILE=../toolchain-aarch64.cmake
make -j$(nproc)

file rpi_app
# rpi_app: ELF 64-bit LSB executable, ARM aarch64...

scp rpi_app pi@<pi-ip-address>:~/
```

---

## 4. Perl — Getting Started

### 4.1 — Verify Perl is Working

```bash
perl --version
# This is perl 5, version 36...

perl -e 'print "Hello from Perl!\n";'
```

---

### 4.2 — Your First Perl Script

```perl
#!/usr/bin/env perl
# hello.pl
use strict;
use warnings;

my $name    = "Developer";
my @langs   = ("C", "C++", "Perl", "PHP", "Python");
my %config  = (debug => 1, port => 8080, host => "localhost");

print "Hello, $name!\n\n";

# Arrays
print "Languages:\n";
foreach my $i (0 .. $#langs) {
    printf "  %d: %s\n", $i, $langs[$i];
}

# Hashes
print "\nConfiguration:\n";
foreach my $key (sort keys %config) {
    printf "  %-8s => %s\n", $key, $config{$key};
}

# String operations
my $str = "  Hello, World!  ";
$str =~ s/^\s+|\s+$//g;     # trim whitespace
print "\nTrimmed: '$str'\n";
print "Uppercase: '" . uc($str) . "'\n";
print "Reversed: '" . scalar(reverse($str)) . "'\n";
```

```bash
chmod +x hello.pl
./hello.pl
# or
perl hello.pl
```

---

### 4.3 — Perl File I/O

```perl
#!/usr/bin/env perl
# file_io.pl
use strict;
use warnings;

my $filename = "/tmp/perl_test.txt";

# Write to file
open(my $fh, '>', $filename) or die "Cannot open $filename: $!";
for my $i (1..5) {
    print $fh "Line $i: The quick brown fox\n";
}
close($fh);
print "Written to $filename\n";

# Read back line by line
open($fh, '<', $filename) or die "Cannot open $filename: $!";
print "\nContents:\n";
while (my $line = <$fh>) {
    chomp $line;
    print "  >> $line\n";
}
close($fh);

# Append
open($fh, '>>', $filename) or die "Cannot open $filename: $!";
print $fh "Line 6: Appended line\n";
close($fh);

unlink $filename;
print "\nFile deleted.\n";
```

```bash
perl file_io.pl
```

---

### 4.4 — Perl with MariaDB (DBI)

```perl
#!/usr/bin/env perl
# db_example.pl
use strict;
use warnings;
use DBI;

my $host = "127.0.0.1";
my $user = "root";
my $pass = "";          # set your root password here
my $db   = "perl_test";

# Connect
my $dbh = DBI->connect(
    "DBI:mysql:host=$host",
    $user, $pass,
    { RaiseError => 1, AutoCommit => 1, PrintError => 0 }
) or die "Cannot connect: $DBI::errstr";

print "Connected to MariaDB.\n";

# Create database and table
$dbh->do("CREATE DATABASE IF NOT EXISTS $db");
$dbh->do("USE $db");
$dbh->do(q{
    CREATE TABLE IF NOT EXISTS products (
        id    INT AUTO_INCREMENT PRIMARY KEY,
        name  VARCHAR(100),
        price DECIMAL(10,2)
    )
});

# Insert with prepared statement
my $sth = $dbh->prepare("INSERT INTO products (name, price) VALUES (?, ?)");
$sth->execute("Raspberry Pi 5",  80.00);
$sth->execute("Arduino Mega",    45.00);
$sth->execute("ESP32 Dev Board", 12.50);
print "Inserted 3 products.\n";

# Select and display
$sth = $dbh->prepare("SELECT id, name, price FROM products ORDER BY price DESC");
$sth->execute();
print "\nProducts:\n";
while (my $row = $sth->fetchrow_hashref()) {
    printf "  [%d] %-20s £%.2f\n", $row->{id}, $row->{name}, $row->{price};
}

# Cleanup
$dbh->do("DROP DATABASE $db");
$dbh->disconnect();
print "\nDone and cleaned up.\n";
```

```bash
perl db_example.pl
```

---

### 4.5 — Perl Regex (Pattern Matching)

```perl
#!/usr/bin/env perl
# regex_example.pl
use strict;
use warnings;

my @lines = (
    "2024-01-15 ERROR  Failed to connect to 192.168.1.100",
    "2024-01-15 INFO   Server started on port 8080",
    "2024-01-15 WARN   Disk usage at 85% on /dev/sda1",
    "2024-01-15 ERROR  Timeout after 30s connecting to db",
    "2024-01-16 INFO   Backup completed successfully",
);

print "Error lines only:\n";
foreach my $line (@lines) {
    if ($line =~ /ERROR/) {
        # Extract date and message
        if ($line =~ /^(\d{4}-\d{2}-\d{2})\s+\w+\s+(.+)$/) {
            print "  Date: $1  Message: $2\n";
        }
    }
}

# Extract IP addresses
print "\nIP addresses found:\n";
foreach my $line (@lines) {
    while ($line =~ /(\d{1,3}\.\d{1,3}\.\d{1,3}\.\d{1,3})/g) {
        print "  $1\n";
    }
}

# Substitution
my $text = "The colour of the favourite flavour";
(my $american = $text) =~ s/colour/color/g;
$american =~ s/favourite/favorite/g;
$american =~ s/flavour/flavor/g;
print "\nOriginal : $text\n";
print "American : $american\n";
```

```bash
perl regex_example.pl
```

---

### 4.6 — Installing Additional Perl Modules

```bash
# Install a module from CPAN
cpanm DateTime
cpanm LWP::UserAgent
cpanm JSON::XS
cpanm DBD::MariaDB

# List installed modules
cpanm --list-installed

# Upgrade a module
cpanm --upgrade DateTime
```

---

## 5. Docker — Getting Started

### 5.1 — Verify Docker is Working

```bash
docker --version
docker compose version

# Run the official hello-world test
docker run hello-world

# Show running containers
docker ps

# Show all containers including stopped
docker ps -a
```

---

### 5.2 — Basic Container Operations

```bash
# Pull an image
docker pull debian:bookworm-slim
docker pull ubuntu:24.04
docker pull alpine:latest

# Run a container interactively (and remove when done)
docker run -it --rm debian:bookworm-slim bash

# Run in the background (detached)
docker run -d --name mycontainer debian:bookworm-slim sleep infinity

# Execute a command in a running container
docker exec -it mycontainer bash

# Stop and remove
docker stop mycontainer
docker rm mycontainer

# List downloaded images
docker images

# Remove an image
docker rmi debian:bookworm-slim
```

---

### 5.3 — Your First Dockerfile (C++ App)

```dockerfile
# Dockerfile
FROM debian:bookworm-slim

# Install build tools
RUN apt-get update && apt-get install -y --no-install-recommends \
    build-essential \
    cmake \
    && rm -rf /var/lib/apt/lists/*

# Set working directory
WORKDIR /app

# Copy source
COPY hello.cpp .

# Build
RUN g++ -std=c++17 -O2 -o hello hello.cpp

# Default command
CMD ["./hello"]
```

```cpp
// hello.cpp
#include <iostream>
int main() {
    std::cout << "Hello from inside Docker!" << std::endl;
    return 0;
}
```

```bash
# Build the image
docker build -t my-cpp-app .

# Run it
docker run --rm my-cpp-app

# Tag for versioning
docker tag my-cpp-app my-cpp-app:v1.0
```

---

### 5.4 — Dockerfile for a PHP Application

```dockerfile
# Dockerfile
FROM php:8.3-cli

WORKDIR /app

COPY index.php .

CMD ["php", "index.php"]
```

```php
<?php
// index.php
echo "Hello from PHP " . PHP_VERSION . " inside Docker!" . PHP_EOL;
echo "Date: " . date('Y-m-d H:i:s') . PHP_EOL;
```

```bash
docker build -t my-php-app .
docker run --rm my-php-app
```

---

### 5.5 — Docker Compose — PHP + MariaDB

This is the most common pattern for a development web stack.

```yaml
# compose.yaml
services:

  db:
    image: mariadb:11
    container_name: mariadb
    restart: unless-stopped
    environment:
      MARIADB_ROOT_PASSWORD: rootpassword
      MARIADB_DATABASE:      myapp
      MARIADB_USER:          appuser
      MARIADB_PASSWORD:      apppassword
    volumes:
      - db_data:/var/lib/mysql
    ports:
      - "3307:3306"       # host port 3307 to avoid clash with local MariaDB

  app:
    image: php:8.3-cli
    container_name: php_app
    depends_on:
      - db
    volumes:
      - ./src:/app        # mount local ./src directory into container
    working_dir: /app
    command: php app.php

volumes:
  db_data:
```

```php
<?php
// src/app.php
$pdo = new PDO(
    'mysql:host=db;dbname=myapp;charset=utf8mb4',
    'appuser',
    'apppassword',
    [PDO::ATTR_ERRMODE => PDO::ERRMODE_EXCEPTION]
);

echo "Connected to MariaDB inside Docker!" . PHP_EOL;
$version = $pdo->query("SELECT VERSION()")->fetchColumn();
echo "MariaDB version: $version" . PHP_EOL;
```

```bash
# Start all services
docker compose up -d

# View logs
docker compose logs -f

# Run a command in the app container
docker compose exec app bash

# Stop everything
docker compose down

# Stop and remove volumes (wipes the database)
docker compose down -v
```

---

### 5.6 — Useful Docker Commands Reference

```bash
# === Images ===
docker images                       # list local images
docker pull nginx:alpine            # download an image
docker rmi <image>                  # remove an image
docker image prune                  # remove unused images

# === Containers ===
docker ps                           # running containers
docker ps -a                        # all containers
docker stop <name>                  # graceful stop
docker kill <name>                  # force stop
docker rm <name>                    # remove stopped container
docker container prune              # remove all stopped containers

# === Logs & Inspection ===
docker logs <name>                  # view logs
docker logs -f <name>               # follow logs (like tail -f)
docker inspect <name>               # full container details (JSON)
docker stats                        # live resource usage (CPU/RAM)
docker top <name>                   # processes inside container

# === Volumes ===
docker volume ls                    # list volumes
docker volume create mydata         # create a volume
docker volume rm mydata             # remove a volume
docker volume prune                 # remove unused volumes

# === Networking ===
docker network ls                   # list networks
docker network create mynet         # create a network
docker run --network mynet ...      # attach container to network

# === System Cleanup ===
docker system prune                 # remove everything unused
docker system prune -a              # remove everything including unused images
docker system df                    # disk usage summary

# === Building ===
docker build -t myapp:latest .      # build from Dockerfile in current dir
docker build -f MyDockerfile .      # specify a different Dockerfile
docker build --no-cache .           # force full rebuild

# === Compose ===
docker compose up -d                # start in background
docker compose down                 # stop and remove containers
docker compose ps                   # status of compose services
docker compose logs -f <service>    # follow logs for one service
docker compose exec <service> bash  # shell into a running service
docker compose build                # rebuild images
```

---

*More examples to be added as the environment is tested and expanded.*
*Tumbleweed-specific notes will be added after cross-platform testing is complete.*
