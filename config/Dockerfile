FROM ubuntu:22.04

# Prevent interactive prompts during installation
ENV DEBIAN_FRONTEND=noninteractive

# Install essential tools and dependencies
RUN apt-get update && apt-get install -y \
    clamav \
    clamav-daemon \
    clamav-freshclam \
    curl \
    wget \
    git \
    unzip \
    build-essential \
    software-properties-common \
    libssl-dev \
    libreadline-dev \
    zlib1g-dev \
    libffi-dev \
    libyaml-dev \
    libsqlite3-dev \
    sqlite3 \
    sqlite3-doc \
    sqlitebrowser \
    && apt-get clean \
    && rm -rf /var/lib/apt/lists/*

# Install additional malware detection tools that work on ARM64
RUN apt-get update && apt-get install -y \
    chkrootkit \
    rkhunter \
    && apt-get clean \
    && rm -rf /var/lib/apt/lists/*

# Install PostgreSQL (client and server)
RUN apt-get update && apt-get install -y \
    postgresql-14 \
    postgresql-client-14 \
    postgresql-contrib-14 \
    libpq-dev \
    && apt-get clean \
    && rm -rf /var/lib/apt/lists/*

# Install MySQL/MariaDB
RUN apt-get update && apt-get install -y \
    mariadb-server \
    mariadb-client \
    libmysqlclient-dev \
    && apt-get clean \
    && rm -rf /var/lib/apt/lists/*

# Install Redis
RUN apt-get update && apt-get install -y \
    redis-server \
    redis-tools \
    && apt-get clean \
    && rm -rf /var/lib/apt/lists/*

# Install Memcached
RUN apt-get update && apt-get install -y \
    memcached \
    libmemcached-tools \
    && apt-get clean \
    && rm -rf /var/lib/apt/lists/*

# Install Elasticsearch dependencies (Java)
RUN apt-get update && apt-get install -y \
    openjdk-11-jre-headless \
    && apt-get clean \
    && rm -rf /var/lib/apt/lists/*

# Install Docker CLI (for Docker-in-Docker support) - Do this early for better caching
RUN apt-get update && apt-get install -y \
    apt-transport-https \
    ca-certificates \
    gnupg \
    lsb-release \
    && curl -fsSL https://download.docker.com/linux/ubuntu/gpg | gpg --dearmor -o /usr/share/keyrings/docker-archive-keyring.gpg \
    && echo "deb [arch=$(dpkg --print-architecture) signed-by=/usr/share/keyrings/docker-archive-keyring.gpg] https://download.docker.com/linux/ubuntu $(lsb_release -cs) stable" | tee /etc/apt/sources.list.d/docker.list > /dev/null \
    && apt-get update \
    && apt-get install -y docker-ce-cli docker-compose-plugin \
    && apt-get clean \
    && rm -rf /var/lib/apt/lists/*

# Install additional useful tools and security scanners - combine into one layer
RUN apt-get update && apt-get install -y \
    vim \
    nano \
    jq \
    tree \
    htop \
    lynis \
    yara \
    shellcheck \
    python3 \
    python3-pip \
    && apt-get clean \
    && rm -rf /var/lib/apt/lists/*

# Install Python security tools
RUN pip3 install --no-cache-dir \
    bandit \
    safety \
    semgrep

# Install specific asdf version manager to avoid migration warnings
RUN git clone https://github.com/asdf-vm/asdf.git ~/.asdf && \
    cd ~/.asdf && \
    git checkout v0.14.1 && \
    echo '. $HOME/.asdf/asdf.sh' >> ~/.bashrc && \
    echo '[ -f ~/.asdf/completions/asdf.bash ] && source ~/.asdf/completions/asdf.bash' >> ~/.bashrc

# Source asdf for the rest of the build
SHELL ["/bin/bash", "-c"]

# Install multiple language versions for compatibility testing
# Combined into single layer for better caching

# Install Node.js versions
RUN source ~/.asdf/asdf.sh && \
    asdf plugin add nodejs https://github.com/asdf-vm/asdf-nodejs.git && \
    asdf install nodejs 22.0.0 && \
    asdf install nodejs 23.6.1 && \
    asdf install nodejs 23.10.0 && \
    asdf install nodejs latest && \
    asdf global nodejs latest

# Install Ruby versions
RUN source ~/.asdf/asdf.sh && \
    asdf plugin add ruby https://github.com/asdf-vm/asdf-ruby.git && \
    export TMPDIR=/var/tmp && \
    asdf install ruby 2.7.5 && \
    asdf install ruby 2.7.7 && \
    asdf install ruby 3.1.4 && \
    asdf install ruby 3.2.0 && \
    asdf install ruby 3.2.2 && \
    asdf install ruby 3.3.0 && \
    asdf install ruby 3.4.3 && \
    asdf install ruby latest && \
    asdf global ruby latest

# Install Python versions
RUN source ~/.asdf/asdf.sh && \
    asdf plugin add python https://github.com/danhper/asdf-python.git && \
    asdf install python 3.10.13 && \
    asdf install python 3.11.9 && \
    asdf install python latest && \
    asdf global python latest

# Install global packages
RUN source ~/.asdf/asdf.sh && \
    npm install -g yarn pnpm && \
    asdf reshim nodejs && \
    gem install bundler && \
    asdf reshim ruby

# Update ClamAV database and YARA rules
RUN freshclam || true
RUN mkdir -p /opt/yara-rules && \
    cd /opt/yara-rules && \
    git clone https://github.com/Yara-Rules/rules.git || true

# Create working directory
WORKDIR /sandbox

# Create database management script
RUN cat > /usr/local/bin/db <<'EOF'
#!/bin/bash

case "$1" in
    start)
        case "$2" in
            postgres|postgresql)
                echo ""
                # Clean up any existing PostgreSQL processes and sockets
                pkill -9 postgres 2>/dev/null || true
                rm -f /tmp/.s.PGSQL.* /var/run/postgresql/.s.PGSQL.* 2>/dev/null || true

                # Ensure runtime directories exist with correct permissions
                mkdir -p /var/run/postgresql /tmp 2>/dev/null || true
                chown postgres:postgres /var/run/postgresql 2>/dev/null || true
                chmod 775 /var/run/postgresql 2>/dev/null || true

                # Start PostgreSQL server
                echo "Starting PostgreSQL..."
                su - postgres -c "/usr/lib/postgresql/14/bin/pg_ctl -D /var/lib/postgresql/14/main -l /tmp/postgres.log start" 2>&1 | grep -v "could not change directory"

                # Wait for PostgreSQL to be ready (up to 15 seconds)
                echo "Waiting for PostgreSQL to be ready..."
                for i in {1..30}; do
                    if psql -U postgres -h 127.0.0.1 -c "SELECT 1" 2>/dev/null | grep -q "1 row"; then
                        echo "✅ PostgreSQL started successfully on port 5432"
                        echo ""
                        echo "Connection info:"
                        echo "  Host: 127.0.0.1"
                        echo "  Port: 5432"
                        echo "  User: postgres"
                        echo "  Password: (none)"
                        echo ""
                        echo "Test with: psql -U postgres -h 127.0.0.1"
                        echo ""
                        echo "💡 For Rails apps, you may need to update config/database.yml:"
                        echo "   Run: rails-db-config"
                        echo ""
                        break
                    fi
                    if [ $i -eq 30 ]; then
                        echo "❌ PostgreSQL failed to start. Checking log..."
                        tail -20 /tmp/postgres.log 2>/dev/null || echo "No log file found"
                        exit 1
                    fi
                    sleep 0.5
                done
                ;;
            mysql|mariadb)
                echo ""
                service mariadb start
                echo "MariaDB/MySQL started on port 3306"
                echo "Connect with: mysql -u root"
                echo ""
                ;;
            redis)
                echo ""
                redis-server --daemonize yes
                echo "Redis started on port 6379"
                echo "Connect with: redis-cli"
                echo ""
                ;;
            memcached)
                echo ""
                service memcached start
                echo "Memcached started on port 11211"
                echo ""
                ;;
            all)
                echo ""
                echo "Starting all databases..."
                $0 start postgres
                $0 start mysql
                $0 start redis
                $0 start memcached
                echo "\nAll databases started"
                ;;
            *)
                echo "Usage: db start [postgres|mysql|redis|memcached|all]"
                ;;
        esac
        ;;
    stop)
        case "$2" in
            postgres|postgresql)
                echo ""
                su - postgres -c "/usr/lib/postgresql/14/bin/pg_ctl -D /var/lib/postgresql/14/main stop" 2>&1 | grep -v "could not change directory" || true
                echo "PostgreSQL stopped"
                echo ""
                ;;
            mysql|mariadb)
                echo ""
                service mariadb stop
                echo "MariaDB/MySQL stopped"
                echo ""
                ;;
            redis)
                echo ""
                redis-cli shutdown
                echo "Redis stopped"
                echo ""
                ;;
            memcached)
                echo ""
                service memcached stop
                echo "Memcached stopped"
                echo ""
                ;;
            all)
                echo ""
                echo "Stopping all databases..."
                $0 stop postgres
                $0 stop mysql
                $0 stop redis
                $0 stop memcached
                echo "\nAll databases stopped"
                ;;
            *)
                echo "Usage: db stop [postgres|mysql|redis|memcached|all]"
                ;;
        esac
        ;;
    status)
        echo ""
        echo "=== Database Status ==="
        echo -n "SQLite3: "
        which sqlite3 > /dev/null && echo "Available (v$(sqlite3 --version | cut -d' ' -f1))" || echo "Not installed"
        echo -n "PostgreSQL: "
        psql -U postgres -h 127.0.0.1 -c "SELECT 1" 2>/dev/null | grep -q "1 row" && echo "Running" || echo "Stopped"
        echo -n "MariaDB/MySQL: "
        service mariadb status | grep -q "running" && echo "Running" || echo "Stopped"
        echo -n "Redis: "
        redis-cli ping 2>/dev/null | grep -q "PONG" && echo "Running" || echo "Stopped"
        echo -n "Memcached: "
        service memcached status | grep -q "running" && echo "Running" || echo "Stopped"
        echo ""
        ;;
    create)
        case "$2" in
            sqlite|sqlite3)
                echo ""
                dbname="${3:-app.db}"
                sqlite3 "$dbname" "CREATE TABLE IF NOT EXISTS test (id INTEGER PRIMARY KEY);"
                echo "SQLite database created: $dbname"
                echo "Connect with: sqlite3 $dbname"
                echo ""
                ;;
            *)
                echo "Usage: db create sqlite [database_name.db]"
                ;;
        esac
        ;;
    *)
        echo ""
        echo "Database Management Tool"
        echo ""
        echo "Usage: db [start|stop|status|create] [database]"
        echo ""
        echo "Databases:"
        echo "  sqlite3    - SQLite3 (embedded, no server needed)"
        echo "  postgres   - PostgreSQL 14 (pre-initialized with UTF8)"
        echo "  mysql      - MariaDB/MySQL"
        echo "  redis      - Redis key-value store"
        echo "  memcached  - Memory caching system"
        echo "  all        - All server databases"
        echo ""
        echo "Examples:"
        echo "  db create sqlite app.db  # Create SQLite database"
        echo "  db start postgres        # Start PostgreSQL server"
        echo "  db stop redis            # Stop Redis server"
        echo "  db status                # Show all database statuses"
        echo "  db start all             # Start all databases"
        echo ""
        echo "PostgreSQL Quick Start:"
        echo "  db start postgres        # Start the server"
        echo "  psql -U postgres -h 127.0.0.1  # Connect to PostgreSQL"
        echo "  rails-db-config          # Configure Rails for PostgreSQL"
        echo ""
        echo "SQLite Quick Start:"
        echo "  sqlite3 development.db   # Open/create database"
        echo "  .help                    # Show SQLite commands"
        echo "  .tables                  # List tables"
        echo ""
        ;;
esac
EOF
RUN chmod +x /usr/local/bin/db

# Pre-initialize PostgreSQL during image build for faster container startup
# This creates the database cluster with UTF8 encoding and trust authentication
RUN mkdir -p /var/lib/postgresql/14/main /var/run/postgresql /tmp && \
    chown -R postgres:postgres /var/lib/postgresql /var/run/postgresql && \
    chmod 775 /var/run/postgresql && \
    chmod 1777 /tmp && \
    su - postgres -c "/usr/lib/postgresql/14/bin/initdb -D /var/lib/postgresql/14/main --encoding=UTF8 --locale=C --auth-local=trust --auth-host=trust" 2>&1 | grep -v "could not change directory" && \
    echo "PostgreSQL initialized during image build"

# Configure PostgreSQL for easy connection
RUN cat > /var/lib/postgresql/14/main/postgresql.conf <<EOF
listen_addresses = '*'
port = 5432
max_connections = 100
shared_buffers = 128MB
dynamic_shared_memory_type = posix
unix_socket_directories = '/var/run/postgresql,/tmp'
log_destination = 'stderr'
logging_collector = off
log_line_prefix = '%m [%p] '
log_timezone = 'UTC'
datestyle = 'iso, mdy'
timezone = 'UTC'
lc_messages = 'C'
lc_monetary = 'C'
lc_numeric = 'C'
lc_time = 'C'
default_text_search_config = 'pg_catalog.english'
EOF

# Setup authentication - trust all for development
RUN cat > /var/lib/postgresql/14/main/pg_hba.conf <<EOF
# TYPE  DATABASE        USER            ADDRESS                 METHOD
local   all             all                                     trust
host    all             all             127.0.0.1/32            trust
host    all             all             0.0.0.0/0               trust
host    all             all             ::1/128                 trust
EOF

# Set correct permissions
RUN chown -R postgres:postgres /var/lib/postgresql/14/main/

# Configure MariaDB for easy access
RUN echo "[mysqld]\nskip-grant-tables" > /etc/mysql/conf.d/easy-access.cnf

# Create a helper script for version switching
RUN cat > /usr/local/bin/versions <<'EOF'
#!/bin/bash
source ~/.asdf/asdf.sh

echo "=== Available Language Versions ==="
echo ""
echo "Node.js versions:"
asdf list nodejs
echo "Current: $(node -v 2>/dev/null || echo 'none')"
echo ""
echo "Ruby versions:"
asdf list ruby
echo "Current: $(ruby -v 2>/dev/null | cut -d' ' -f2 || echo 'none')"
echo ""
echo "Python versions:"
asdf list python
echo "Current: $(python --version 2>/dev/null | cut -d' ' -f2 || echo 'none')"
echo ""
echo "=== Quick Commands (Modern Syntax) ==="
echo "Set for current directory:"
echo "  asdf set nodejs <version>    (e.g., asdf set nodejs 20.0.0)"
echo "  asdf set ruby <version>      (e.g., asdf set ruby 3.2.2)"
echo "  asdf set python <version>    (e.g., asdf set python 3.11.9)"
echo ""
echo "Set global default:"
echo "  asdf global nodejs <version>"
echo "  asdf global ruby <version>"
echo "  asdf global python <version>"
echo ""
echo "Install new version: asdf install <language> <version>"
echo "List all available: asdf list all <language>"
EOF
RUN chmod +x /usr/local/bin/versions

# Create Rails database configuration script
RUN cat > /usr/local/bin/rails-db-config <<'EOF'
#!/bin/bash

# Simple script to add PostgreSQL connection settings to Rails database.yml
CONFIG_FILE="${1:-config/database.yml}"

echo ""

if [ ! -f "$CONFIG_FILE" ]; then
    echo "❌ Error: database.yml not found at: $CONFIG_FILE"
    echo ""
    echo "Usage: rails-db-config [path/to/database.yml]"
    echo "   or run from Rails root directory"
    echo ""
    exit 1
fi

echo "📝 Updating $CONFIG_FILE for PostgreSQL in Docker..."

# Create backup with timestamp
BACKUP_FILE="${CONFIG_FILE}.backup.$(date +%Y%m%d_%H%M%S)"
cp "$CONFIG_FILE" "$BACKUP_FILE"
echo "  ✓ Backup created: $BACKUP_FILE"

# Add PostgreSQL connection settings if not already present
if ! grep -q "host: 127.0.0.1" "$CONFIG_FILE"; then
    # Use awk to properly add settings after adapter lines
    awk '
    /^[[:space:]]*adapter:[[:space:]]*postgresql/ {
        print
        in_pg_section = 1
        next
    }
    in_pg_section && /^[[:space:]]*encoding:/ {
        print
        print "  host: 127.0.0.1"
        print "  username: postgres"
        in_pg_section = 0
        next
    }
    { print }
    ' "$CONFIG_FILE" > "${CONFIG_FILE}.tmp" && mv "${CONFIG_FILE}.tmp" "$CONFIG_FILE"
    echo "  ✓ Added PostgreSQL connection settings"
else
    echo "  ✓ Already configured"
fi

echo ""
echo "✅ Configuration complete!"
echo ""
echo "Next steps:"
echo "  1. Start PostgreSQL: db start postgres"
echo "  2. Create database: bin/rails db:create"
echo "  3. Run migrations: bin/rails db:migrate"
echo "  4. Start Rails: bin/rails server -b 0.0.0.0"
echo ""
EOF
RUN chmod +x /usr/local/bin/rails-db-config

# Create terminal connection helper script
RUN cat > /usr/local/bin/terminal <<'EOF'
#!/bin/bash
echo ""
echo "================================================"
echo "🖥️  Open Another Terminal in This Container"
echo "================================================"
echo ""
echo "To connect another terminal to this container, run:"
echo ""
echo "  docker exec -it $(hostname) bash"
echo ""
echo "Container ID: $(hostname)"
echo ""
echo "This allows you to have multiple terminal windows"
echo "working in the same isolated environment."
echo ""
echo "================================================"
EOF
RUN chmod +x /usr/local/bin/terminal

# Create dev server helper script (simplified)
RUN cat > /usr/local/bin/serve <<'EOF'
#!/bin/bash
echo ""
echo "================================================"
echo "🚀 Dev Server Commands Reference"
echo "================================================"
echo ""
echo "Common commands to start dev servers:"
echo ""
echo "  Vite:                 yarn dev --host"
echo "  Create React App:     HOST=0.0.0.0 npm start"
echo "  Next.js:              yarn dev"
echo "  Rails:                bundle exec rails s -b 0.0.0.0"
echo "  Django:               python manage.py runserver 0.0.0.0:8000"
echo "  Flask:                flask run --host=0.0.0.0"
echo "  Express:              npm start"
echo ""
echo "📍 For Rails apps using bin/dev with foreman:"
echo "   export BINDING=0.0.0.0"
echo "   export HOST=0.0.0.0"
echo "   bin/dev"
echo ""
echo "📝 Note: Apps must bind to 0.0.0.0 (not localhost) inside Docker."
echo "   Access them via the mapped ports shown when you started the container."
echo ""
echo "================================================"
EOF
RUN chmod +x /usr/local/bin/serve

# Create asdf set command alias for modern syntax
RUN cat > /usr/local/bin/asdf-set-wrapper <<'EOF'
#!/bin/bash
# Wrapper to ensure 'asdf set' works as an alias to 'asdf local'
if [ "$1" = "set" ]; then
    shift
    asdf local "$@"
else
    asdf "$@"
fi
EOF
RUN chmod +x /usr/local/bin/asdf-set-wrapper

# Ensure asdf is loaded in bash sessions with modern syntax support
RUN echo 'source ~/.asdf/asdf.sh' >> ~/.bashrc && \
    echo '[ -f ~/.asdf/completions/asdf.bash ] && source ~/.asdf/completions/asdf.bash' >> ~/.bashrc && \
    echo 'alias asdf="/usr/local/bin/asdf-set-wrapper"' >> ~/.bashrc && \
    echo 'echo ""' >> ~/.bashrc && \
    echo 'echo "================================================"' >> ~/.bashrc && \
    echo 'echo "   Isolated Sandbox Environment Ready"' >> ~/.bashrc && \
    echo 'echo "================================================"' >> ~/.bashrc && \
    echo 'echo ""' >> ~/.bashrc && \
    echo 'echo "Quick Commands:"' >> ~/.bashrc && \
    echo 'echo "  serve            - Show dev server commands reference"' >> ~/.bashrc && \
    echo 'echo "  versions         - Show available language versions"' >> ~/.bashrc && \
    echo 'echo "  db               - Manage databases (postgres, mysql, redis)"' >> ~/.bashrc && \
    echo 'echo "  rails-db-config  - Auto-configure Rails for PostgreSQL"' >> ~/.bashrc && \
    echo 'echo "  terminal         - Show how to open another terminal here"' >> ~/.bashrc && \
    echo 'echo ""' >> ~/.bashrc && \
    echo 'echo "Examples:"' >> ~/.bashrc && \
    echo 'echo "  asdf set ruby 3.2.2       # Switch Ruby version"' >> ~/.bashrc && \
    echo 'echo "  db start postgres         # Start PostgreSQL"' >> ~/.bashrc && \
    echo 'echo ""' >> ~/.bashrc && \
    echo 'echo "================================================"' >> ~/.bashrc && \
    echo 'echo ""' >> ~/.bashrc

CMD ["/bin/bash"]
